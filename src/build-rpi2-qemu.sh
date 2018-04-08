#!/bin/sh

set -exm

# User configurable variables
KERNEL_IMAGE="kernel-qemu-4.9.59-stretch"
RASPIAN_DATE="2018-03-13"
RASPIAN_URL="http://director.downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2018-03-14"

SSH="ssh -p 2222 -o StrictHostKeyChecking=no"
SCP="scp -P 2222 -o StrictHostKeyChecking=no"
RASPIAN_ZIP=${RASPIAN_DATE}-raspbian-stretch-lite.zip
RASPIAN_IMAGE=${RASPIAN_DATE}-raspbian-stretch-lite.img


ssh_control()
{
    set +ex
    while :; do
	${SSH} pi@localhost ls 2>&1 >/dev/null
	if [ $? -eq 0 ]; then
	    break
	fi
	sleep 1
    done
    set -ex
    cat <<EOF > script
    sudo apt install -y python3-pip python3-pyqt5 libusb-1.0 \
	    libblas-dev liblapack-dev libatlas-base-dev gfortran
    pip3 install -r artisan/src/requirements.txt
    (cd Phidget22Python && sudo python3 setup.py install)
    cd artisan/src
    ./build-centos-pi.sh
    ./build-rpi2-deb.sh
EOF
    ${SCP} script pi@localhost:
    ${SSH} pi@localhost sh script
    ${SCP} pi@localhost:artisan/src/\*.deb .
    pkill qemu-system-arm
}

ssh-keygen -R "[localhost]:2222"
curl -L -O ${RASPIAN_URL}/${RASPIAN_ZIP}
unzip ${RASPIAN_ZIP}
curl -L -O https://github.com/juokelis/qemu-rpi-kernel/raw/master/${KERNEL_IMAGE}
curl -L -O https://github.com/juokelis/qemu-rpi-kernel/raw/master/versatile-pb.dtb
qemu-img resize ${RASPIAN_IMAGE} +2G
partitions=`mktemp`
cat <<EOF > $partitions
label: dos
label-id: 0xa8fe70f4
device: 2018-03-13-raspbian-stretch-lite.img
unit: sectors

2018-03-13-raspbian-stretch-lite.img1 : start=        8192, size=       85611, type=c
2018-03-13-raspbian-stretch-lite.img2 : start=       98304, size=     7725056, type=83
EOF
if [ -f util-linux*/sfdisk ]; then
    util-linux*/sfdisk  ${RASPIAN_IMAGE} < $partitions
else
    sfdisk  ${RASPIAN_IMAGE} < $partitions
fi
rm $partitions
sudo losetup -o $((98304*512)) /dev/loop0 ${RASPIAN_IMAGE}
sudo e2fsck -fy /dev/loop0 || true
sudo resize2fs /dev/loop0
mountpoint=`mktemp -d`
sudo mount /dev/loop0 $mountpoint
sudo sed -i'' -e 's/exit 0/\/etc\/init.d\/ssh start/' $mountpoint/etc/rc.local
sudo mkdir $mountpoint/home/pi/.ssh
sudo chown 1000  $mountpoint/home/pi/.ssh
sudo chmod go-rwx $mountpoint/home/pi/.ssh
cat /dev/zero | ssh-keygen -q -N "" || true
sudo cp $HOME/.ssh/id_rsa.pub $mountpoint/home/pi/.ssh/authorized_keys
sudo mkdir $mountpoint/home/pi/artisan
if [ -d src ]; then
    sudo cp -R ../artisan/src $mountpoint/home/pi/artisan
    sudo cp -R ../artisan/LICENSE $mountpoint/home/pi/artisan
elif [ -f artisan.py ]; then
    sudo cp -R ../../artisan/src $mountpoint/home/pi/artisan
    sudo cp -R ../../artisan/LICENSE $mountpoint/home/pi/artisan
fi
cd $mountpoint/home/pi
sudo curl -L -O https://dl.bintray.com/artisan/artisan-cache/libsnap.tar.gz
sudo tar -C $mountpoint/usr/lib -xzf libsnap.tar.gz
sudo curl -L -O https://dl.bintray.com/artisan/artisan-cache/libphidget22.tar.gz
sudo tar -C $mountpoint/usr/lib -xzf libphidget22.tar.gz
sudo curl -L -O https://www.phidgets.com/downloads/phidget22/libraries/any/Phidget22Python.zip
sudo unzip -q Phidget22Python.zip
sudo curl -L -O https://dl.bintray.com/artisan/artisan-cache/pip-cache.tar.gz   
sudo tar -xzpf pip-cache.tar.gz
sudo rm pip-cache.tar.gz
sudo chown -R 1000 .
sudo curl -L -O https://dl.bintray.com/artisan/artisan-cache/apt-cache.tar.gz
sudo tar -C $mountpoint -xzpf apt-cache.tar.gz
sudo rm apt-cache.tar.gz
cd -
sudo umount $mountpoint
sudo losetup -d /dev/loop0
rmdir $mountpoint

ssh_control &
qemu-system-arm -kernel ${KERNEL_IMAGE} -dtb versatile-pb.dtb -cpu arm1176 -m 256 -M versatilepb -no-reboot -nographic -append "root=/dev/sda2 panic=1 rootfstype=ext4 rw" -hda ${RASPIAN_IMAGE} -redir tcp:2222::22