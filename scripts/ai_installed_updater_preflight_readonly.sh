#!/bin/sh
# Read-only minimal iStoreOS actual installed-updater provenance check.
# Not an update/download/reload/hook install. No source content is printed.
umask 077
echo 'UPDATER_PREFLIGHT=START READ_ONLY=YES'
file='/usr/share/openclash/openclash.sh'
if [ ! -r "$file" ]; then
  echo 'INSTALLED_UPDATER=NOT_READABLE'
elif ! command -v sha1sum >/dev/null 2>&1; then
  echo 'INSTALLED_UPDATER=READABLE BLOB_SHA=HASH_TOOL_UNAVAILABLE'
elif ! command -v wc >/dev/null 2>&1; then
  echo 'INSTALLED_UPDATER=READABLE BLOB_SHA=HASH_TOOL_UNAVAILABLE'
else
  bytes=$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')
  case "$bytes" in
    ''|*[!0-9]*)
      echo 'INSTALLED_UPDATER=READABLE BLOB_SHA=READ_ERROR'
      ;;
    *)
      raw=$( { printf 'blob %s\000' "$bytes"; cat "$file"; } | sha1sum 2>/dev/null)
      sum=$(printf '%s\n' "$raw" | awk '{print $1}')
      case "$sum" in
        ''|*[!0-9a-f]*)
          echo 'INSTALLED_UPDATER=READABLE BLOB_SHA=UNAVAILABLE'
          ;;
        *)
          if [ "$(printf '%s' "$sum" | wc -c)" -ne 40 ]; then
            echo 'INSTALLED_UPDATER=READABLE BLOB_SHA=UNAVAILABLE'
          elif [ "$sum" = '6c181265ca96c452660653d60ec552d58eccc12c' ]; then
            echo "INSTALLED_UPDATER=PINNED_UPSTREAM_OCT2026 GIT_BLOB_SHA=$sum"
          else
            echo "INSTALLED_UPDATER=DIFFERENT_VERSION GIT_BLOB_SHA=$sum"
          fi
          ;;
      esac
      ;;
  esac
fi
if command -v ruby >/dev/null 2>&1; then
ruby <<'RUBY'
begin
  a=File.binread('/proc/self/auxv',16384)
  w=[0].pack('J').bytesize
  pairs=a.bytesize>0 && a.bytesize%(2*w)==0 ? a.unpack('J*').each_slice(2).to_a : []
  i=pairs.index{|p|p[0]==0}
  valid=i && i>0 && pairs.drop(i).all?{|p|p==[0,0]}
  clocks=valid ? pairs.take(i).select{|p|p[0]==17}.map(&:last) : []
  hz=clocks.size==1 && clocks.first.between?(10,10000) ? clocks.first : nil
  puts "KERNEL_AT_CLKTCK=#{hz || 'UNAVAILABLE'}"
rescue StandardError
  puts 'KERNEL_AT_CLKTCK=UNAVAILABLE'
end
RUBY
else
  echo 'KERNEL_AT_CLKTCK=RUBY_UNAVAILABLE'
fi
echo 'UPDATER_PREFLIGHT=FINISHED PRODUCTION_WRITES=NONE'
