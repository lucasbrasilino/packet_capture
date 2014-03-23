#!/usr/bin/env python

from NFTest import *
import sys
import os
from scapy.layers.all import Ether, IP, TCP
from reg_defines_reference_nic import *

conn = ('../connections/conn', [])
#nftest_init(sim_loop = ['nf0','nf1','nf2','nf3'], hw_config = [conn])
nftest_init()
nftest_start()

# set parameters
SA = "aa:bb:cc:dd:ee:ff"
TTL = 64
DST_IP = "192.168.1.1"
SRC_IP = "192.168.0.1"
NUM_PKTS = 2
DEV_NUM  = 1 #sending only through nf0 DMA queue 


pkts = []
print "Sending now: "
for j in range (DEV_NUM):
	pkts.append([])
	for i in range(NUM_PKTS):
    		sys.stdout.write('\r'+str(i))
    		sys.stdout.flush()
    		DA = "d%d:f%d:fe:00:00:00" % (j,i)
    		pkt = make_IP_pkt(dst_MAC=DA, src_MAC=SA, dst_IP=DST_IP,
                      src_IP=SRC_IP, TTL=TTL,pkt_len=60) 
    		pkt.time = (j*(1e-8)+i*(1e-8))
    		pkts[j].append(pkt)

for j in range (DEV_NUM):
	iface = "nf%d" % j
	nftest_send_phy(iface,pkts[j])
        nftest_expect_dma(iface,pkts[j])
	nftest_expect_dma("nf3",pkts[j])
mres=[]
nftest_finish(mres)
