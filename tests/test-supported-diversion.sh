#!/bin/bash
# divtest.sh <pkgdir>: postinst configure, then postrm remove + purge (what apt purge does); the stock SUPPORTED must survive
P=$1; T=$(mktemp -d); mkdir -p $T/var/lib/dpkg $T/usr/share/i18n $T/bin; touch $T/var/lib/dpkg/diversions
printf 'en_US.UTF-8 UTF-8\nit_IT.UTF-8 UTF-8\nde_DE ISO-8859-1\n' > $T/usr/share/i18n/SUPPORTED; cp $T/usr/share/i18n/SUPPORTED $T/stock
cat > $T/bin/dpkg-divert <<SH
#!/bin/bash
a=(); for x in "\$@"; do a+=("\${x#$T}"); done; exec /usr/bin/dpkg-divert --root $T "\${a[@]}"
SH
chmod +x $T/bin/dpkg-divert
for s in postinst postrm; do sed "s#=/usr/share#=$T/usr/share#g" $P/debian/$s > $T/$s; done
PATH=$T/bin:$PATH sh -e $T/postinst configure; grep -q '^en UTF-8$' $T/usr/share/i18n/SUPPORTED && echo "after configure: bare tags present"
PATH=$T/bin:$PATH sh -e $T/postrm remove; echo "after remove: $(cmp -s $T/stock $T/usr/share/i18n/SUPPORTED && echo stock || echo NOT-stock)"
PATH=$T/bin:$PATH sh -e $T/postrm purge; r=1; cmp -s $T/stock $T/usr/share/i18n/SUPPORTED && r=0
echo "after purge: $([ $r = 0 ] && echo stock || echo MISSING-or-changed); diversions: $(wc -l < $T/var/lib/dpkg/diversions) lines"
rm -rf $T; exit $r
