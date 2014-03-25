/*******************************************************************************
 *
 *  NetFPGA-10G http://www.netfpga.org
 *
 *  File:
 *        capture_interface.c
 *
 *  Project:
 *        nic
 *
 *  Author:
 *        Lucas Brasilino
 *
 *  Description:
 *        Defines which interface should be sent the captured packets
 *
 *  Licence:
 *        This file is part of the NetFPGA 10G development base package.
 *
 *        This file is free code: you can redistribute it and/or modify it under
 *        the terms of the GNU Lesser General Public License version 2.1 as
 *        published by the Free Software Foundation.
 *
 *        This package is distributed in the hope that it will be useful, but
 *        WITHOUT ANY WARRANTY; without even the implied warranty of
 *        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *        Lesser General Public License for more details.
 *
 *        You should have received a copy of the GNU Lesser General Public
 *        License along with the NetFPGA source package.  If not, see
 *        http://www.gnu.org/licenses/.
 *
 */

#include <fcntl.h>
#include <sys/ioctl.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "../reg_defines.h"

#define NF10_IOCTL_CMD_READ_STAT (SIOCDEVPRIVATE+0)
#define NF10_IOCTL_CMD_WRITE_REG (SIOCDEVPRIVATE+1)
#define NF10_IOCTL_CMD_READ_REG (SIOCDEVPRIVATE+2)

int main(int argc, char **argv) {
	int f;
	uint64_t v;
	uint64_t val;

	if(argc < 2) {
		fprintf(stderr,"Usage: ./pkt_capt_odq [0x80 (nf3) | 0x20 (nf2) | "
				" (0x08) nf1| (0x02) nf0]\n");
		return 1;
	} else {
		sscanf(++*argv,"%llx",&val);
	}
	f = open("/dev/nf10", O_RDWR);
	if(f < 0) {
	    perror("/dev/nf10");
	    return 1;
	}
	v = XPAR_PACKET_CAPTURE_0_BASEADDR;
	v = (v<<32) + val;
	if(ioctl(f, NF10_IOCTL_CMD_WRITE_REG, v) < 0) {
		perror("nf10 ioctl failed");
	    return 1;
	}
	close(f);

	return 0;
}
