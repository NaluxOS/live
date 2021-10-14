# Nalux Build Scripts

## build.sh

```
This script builds a bootable Nalux ISO image

Supported commands : setup_host debootstrap run_chroot build_iso

Syntax: ./build.sh [start_cmd] [-] [end_cmd]
	run from start_cmd to end_end
	if start_cmd is omitted, start from first command
	if end_cmd is omitted, end with last command
	enter single cmd to run the specific command
	enter '-' as only argument to run all commands
```

## Other info

This script is meant to be run on Ubuntu or Debian based systems - other systems could work but are neither tested nor supported. The script pulls all dependencies automatically via apt.

The build script is not fully automatic as locale config and resolvconf need user input. This is to be fixed soon.

Also, please be make sure that, if you plan to use chroot_build.sh manually (which is not recommended), you are actually in a chroot because the script does not check for that. Otherwise it might install unwanted packages on your main machine.

## Credits

This build script is based on Marcos Tischer Vallim's [live-custom-ubuntu-from-scratch script](https://github.com/mvallim/live-custom-ubuntu-from-scratch/tree/master/scripts).
