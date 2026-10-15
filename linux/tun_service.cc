#include <fcntl.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#include <iostream>

extern "C" {

/// Allocates a raw TUN device via /dev/net/tun.
/// 
/// Note: Executable must have cap_net_admin+ep capabilities.
/// Run: sudo setcap cap_net_admin+ep ./candyconnect
/// 
/// Returns the file descriptor for the TUN interface on success, -1 on failure.
int allocate_tun_device(const char* dev_name) {
    struct ifreq ifr;
    int fd, err;
    const char *clonedev = "/dev/net/tun";

    // Open the clone device
    if( (fd = open(clonedev, O_RDWR)) < 0 ) {
        std::cerr << "CandyConnect [Linux TUN]: Failed to open /dev/net/tun. Ensure cap_net_admin+ep is set." << std::endl;
        return fd; // returning -1
    }

    // Prepare the ifreq struct for a TUN device, explicitly without packet info
    memset(&ifr, 0, sizeof(ifr));
    ifr.ifr_flags = IFF_TUN | IFF_NO_PI;

    // Set custom device name if provided
    if (dev_name && *dev_name) {
        strncpy(ifr.ifr_name, dev_name, IFNAMSIZ);
        ifr.ifr_name[IFNAMSIZ - 1] = '\0';
    }

    // Try to create the device
    if( (err = ioctl(fd, TUNSETIFF, (void *) &ifr)) < 0 ) {
        std::cerr << "CandyConnect [Linux TUN]: ioctl(TUNSETIFF) failed." << std::endl;
        close(fd);
        return err; // returning negative error code
    }

    std::cout << "CandyConnect [Linux TUN]: Successfully allocated interface " << ifr.ifr_name << std::endl;

    // Return the fd; Dart side can inject this into env["xray.tun.fd"]
    return fd;
}

}
