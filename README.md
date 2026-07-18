# MuliOS Update

> The official update repository for **MuliOS**.

This repository contains update packages used by MuliOS to deliver new features, bug fixes, security patches, profile optimizations, and application changes.

---

MuliOS Update is responsible for distributing updates to all MuliOS installations.

Updates can include:

-  Bug fixes
-  Performance improvements
-  Security patches
-  Profile improvements
-  Application installation/removal
-  System configuration changes

The MuliOS Update client downloads update packages directly from this repository and applies them automatically.

---

## How Updates Work

1. mupdate checks for updates.
3. Required update package(s) are downloaded.
4. The update engine executes the package.
5. The system is updated without reinstalling MuliOS.

---

*quick reminder that updates may or may not cause harm to the OS. for this reason, the generic kernel is kept as a back up fix.*

## Manual updates

For manual updates, please go in the profiles folder and go into any profile that is currently used on your hardware. you can find your kernel in use using
```uname -r```. reminder that you cannot go from profile1 to profile2, and you must always reach towards the generic kernel inbetween jumps.

you can then download the latest zip package and install both debian packages. (headers first then image) you can also run the install.sh script which is recommended since it follows the mupdate procedure.
