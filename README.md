## ctmg

`ctmg` is an encrypted container manager for Linux using `cryptsetup` and various standard file system utilities. Containers have the extension `.ct` and are mounted at a directory of the same name, but without the extension. Very simple to understand, and very simple to implement; `ctmg` is a simple bash script.

### Usage

    Usage: ctmg [ new | delete | open | close | list ] [arguments...]
      ctmg new    container_path container_size[units_suffix]
      ctmg delete container_path
      ctmg open   container_path
      ctmg close  container_path
      ctmg list

### Examples

#### Create a 100MiB encrypted container called "example"

    zx2c4@thinkpad ~ $ ctmg create example 100MiB
    [#] truncate -s 100MiB /home/zx2c4/example.ct
    [#] cryptsetup --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 5000 --batch-mode luksFormat /home/zx2c4/example.ct
    Enter passphrase:
    [#] chown 1000:1000 /home/zx2c4/example.ct
    [#] cryptsetup luksOpen /home/zx2c4/example.ct ct_example
    Enter passphrase for /home/zx2c4/example.ct:
    [#] mkfs.ext4 -q -E root_owner=1000:1000 /dev/mapper/ct_example
    [+] Created new encrypted container at /home/zx2c4/example.ct
    [#] cryptsetup luksClose ct_example

#### Open a container, add a file, and then close it

    zx2c4@thinkpad ~ $ ctmg open example
    [#] cryptsetup luksOpen /home/zx2c4/example.ct ct_example
    Enter passphrase for /home/zx2c4/example.ct: 
    [#] mkdir -p /home/zx2c4/example
    [#] mount /dev/mapper/ct_example /home/zx2c4/example
    [+] Opened /home/zx2c4/example.ct at /home/zx2c4/example
    zx2c4@thinkpad ~ $ echo "super secret" > example/mysecretfile.txt
    zx2c4@thinkpad ~ $ ctmg close example
    [#] umount /home/zx2c4/example
    [#] cryptsetup luksClose ct_example
    [#] rmdir /home/zx2c4/example
    [+] Closed /home/zx2c4/example.ct

### Installation

    # make install

Or, use the package from your distribution:

#### Gentoo

    # emerge ctmg

### Bug reports

Report any bugs to <jason@zx2c4.com>.
