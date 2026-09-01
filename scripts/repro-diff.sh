#!/usr/bin/env bash
# What differs between two builds of one derivation, said precisely enough to
# start on the fix without downloading anything.
#
# WHY: nix's own verdict is one line -- "may not be deterministic" -- and a
# reproducibility failure is only actionable once you know WHERE the bytes
# moved. A handful of bytes in .comment is a toolchain stamp; a diff spread
# across .text is codegen nondeterminism; a diff confined to .rodata with the
# same symbol names is usually an embedded path or timestamp. Bucketing the
# differing bytes by ELF section, using the first build's layout, answers that
# in the job log instead of after a diffoscope round trip.
#
# usage: repro-diff.sh REFERENCE REBUILT   (two output trees, e.g. $out $out.check)
# Prints markdown; the workflow tees it into the job summary. Linux/ELF only,
# the same limit as the repro workflow itself, and for the same reason.
set -euo pipefail
# Fixes diff's message wording and quoting, which the parsing below depends on.
export LC_ALL=C

a=$1
b=$2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# `cmp` and `diff` exit 1 to mean "these differ", which is the answer we came
# for, not an error. Anything above 1 is a real failure and still propagates.
differ() {
	"$@" || [ $? -eq 1 ]
}

# Absolute 1-based byte offsets of every difference inside [off, off+size) of
# both files, printed as "count first-offset". cmp reports positions relative
# to the skipped prefix, hence the arithmetic.
diff_range() {
	differ cmp -l -i "$3" -n "$4" "$1" "$2" 2>/dev/null |
		awk -v off="$3" 'NR == 1 { first = $1 } END { if (NR) printf "%d %#x", NR, first - 1 + off }'
}

is_elf() {
	[ "$(head -c 4 "$1" | tr -d '\0')" = $'\x7fELF' ]
}

# Symbol names present in one build but not the other. A stripped binary has
# no names to compare, which is a property of the input, not a failure here.
name_diff() {
	nm -j "$1" 2>/dev/null | sort >"$tmp/names.a" || :
	nm -j "$2" 2>/dev/null | sort >"$tmp/names.b" || :
	echo "$(comm -23 "$tmp/names.a" "$tmp/names.b" | wc -l | tr -d ' ') / $(comm -13 "$tmp/names.a" "$tmp/names.b" | wc -l | tr -d ' ')"
}

# Section table of the reference, as "name offset size" in decimal, file-backed
# sections only (NOBITS such as .bss occupies no bytes on disk). The two gaps
# the table does not name -- the ELF and program headers before the first
# section, and the section-header table after the last -- are added so every
# differing byte lands somewhere.
sections() {
	{
		readelf -SW "$1" | sed -E 's/^ *\[ *[0-9]+\] *//' |
			while read -r name type _ off size _; do
				[ "$type" != NOBITS ] && [[ $off =~ ^[0-9a-f]+$ && $size =~ ^[0-9a-f]+$ ]] || continue
				if [ $((16#$size)) -gt 0 ]; then
					echo "$name $((16#$off)) $((16#$size))"
				fi
			done
		local header shoff shnum shentsize
		header=$(readelf -h "$1")
		shoff=$(awk '/Start of section headers/ { print $5 }' <<<"$header")
		shnum=$(awk '/Number of section headers/ { print $5 }' <<<"$header")
		shentsize=$(awk '/Size of section headers/ { print $5 }' <<<"$header")
		echo "section-headers $shoff $((shnum * shentsize))"
	} | sort -k2,2n
}

buckets() {
	local first_section
	first_section=$(sections "$1" | awk 'NR == 1 { print $2 }')
	{
		echo "elf+program-headers 0 $first_section"
		sections "$1"
	} | while read -r name off size; do
		r=$(diff_range "$1" "$2" "$off" "$size")
		if [ -n "$r" ]; then
			echo "| $name | ${r% *} | ${r#* } |"
		fi
	done
}

# `diff -rq` names things three ways -- "Files A and B differ", "Symbolic links
# A and B differ", "Only in DIR: name" -- and this turns each into a path
# relative to the tree, so the table reads the same however the file differs.
relative() {
	local rel=${1#"$a"}
	rel=${rel#"$b"}
	rel=${rel#: }
	rel=${rel/: //}
	echo "${rel#/}"
}

differ diff -rq --no-dereference "$a" "$b" >"$tmp/files"

echo
echo "| file | reference | rebuilt | differing bytes | names only in ref / only in rebuilt |"
echo "|---|---|---|---|---|"
while read -r line; do
	case $line in
	"Only in $a"*) echo "| $(relative "${line#Only in }") | present | absent | | |" ;;
	"Only in $b"*) echo "| $(relative "${line#Only in }") | absent | present | | |" ;;
	"Symbolic links "*)
		f=${line#Symbolic links }
		f=${f%% ->*}
		f=$(relative "${f//[\'\"‘’]/}")
		echo "| $f | -> $(readlink "$a/$f") | -> $(readlink "$b/$f") | | |"
		;;
	"Files "*)
		f=$(relative "${line#Files }")
		f=${f%% and *}
		bytes=$(differ cmp -l "$a/$f" "$b/$f" 2>/dev/null | wc -l | tr -d ' ')
		names=""
		if is_elf "$a/$f"; then
			names=$(name_diff "$a/$f" "$b/$f")
		fi
		echo "| $f | $(stat -c %s "$a/$f") B | $(stat -c %s "$b/$f") B | $bytes | $names |"
		;;
	esac
done <"$tmp/files"

while read -r line; do
	case $line in
	"Files "*)
		f=$(relative "${line#Files }")
		f=${f%% and *}
		is_elf "$a/$f" || continue
		echo
		echo "$f, differing bytes by section of the reference:"
		echo
		echo "| section | differing bytes | first diff |"
		echo "|---|---|---|"
		buckets "$a/$f" "$b/$f"
		;;
	esac
done <"$tmp/files"
