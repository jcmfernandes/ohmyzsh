otherplug_hello() { print "hello from otherplug" }
otherplug_plugin_unload() {
  typeset -ga UNLOAD_ORDER
  UNLOAD_ORDER+=("otherplug")
}
