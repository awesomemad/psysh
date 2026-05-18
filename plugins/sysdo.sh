sudo() {
  runas /user:Administrator "$@"
}
sysdo() {
  /c/users/keleb/psexec64 -i -d -s $@
}
