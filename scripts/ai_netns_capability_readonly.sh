#!/bin/sh
# iStoreOS zero-secret network-namespace admission, NOT a sandbox proof.
# No user config/cache reads, no socket traffic, no Mihomo invocation,
# no netlink changes to the original namespace.
echo 'NETNS_CAPABILITY_PROBE=START PRIVATE_CONFIG_READ=NO'
if ! command -v unshare >/dev/null 2>&1; then
  echo 'NETNS_RESULT=HOLD_TOOL_UNAVAILABLE'
elif ! command -v readlink >/dev/null 2>&1; then
  echo 'NETNS_RESULT=HOLD_READLINK_UNAVAILABLE'
elif [ ! -r /proc/self/ns/net ]; then
  echo 'NETNS_RESULT=HOLD_PROC_NS_UNAVAILABLE'
else
  parent="$(readlink /proc/self/ns/net 2>/dev/null)" || parent=''
  if [ -z "$parent" ]; then
    echo 'NETNS_RESULT=HOLD_PARENT_NS_UNKNOWN'
  elif unshare -n sh -c '
      child="$(readlink /proc/self/ns/net 2>/dev/null)" || exit 2
      [ -n "$child" ] && [ "$child" != "$1" ]
    ' check "$parent" >/dev/null 2>&1; then
    echo 'NETNS_RESULT=CHILD_NAMESPACE_DISTINCT'
  else
    echo 'NETNS_RESULT=HOLD_NEW_NAMESPACE_UNAVAILABLE'
  fi
fi
echo 'NETWORK_EGRESS_DENIAL=NOT_PROVEN'
echo 'ROUTER_CONFIG=UNCHANGED RULE_CACHES=NOT_READ'
echo 'PRIVATE_CONFIG_TEST=NOT_RUN LISTENER_INSTALLED=NO AUTO_SWITCH=OFF'
