# Nalux Build Scripts

## build.sh

```
This script builds a bootable Nalux ISO image

Syntax: ./build.sh

The final iso will be found in ./out/
```

## Other info
Please be make sure that, if you plan to use chroot_build.sh manually (which is not recommended), you are actually in a chroot because the script does not check for that. Otherwise it might install unwanted packages on your main machine.

## Credits

This build script is based on Marcos Tischer Vallim's [live-custom-ubuntu-from-scratch script](https://github.com/mvallim/live-custom-ubuntu-from-scratch/tree/master/scripts).
