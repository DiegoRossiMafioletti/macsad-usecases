/* Copyright 2018 INTRIG/FEEC/UNICAMP (University of Campinas), Brazi      */
/*                                                                         */
/*Licensed under the Apache License, Version 2.0 (the "License");          */
/*you may not use this file except in compliance with the License.         */
/*You may obtain a copy of the License at                                  */
/*                                                                         */
/*    http://www.apache.org/licenses/LICENSE-2.0                           */
/*                                                                         */
/*Unless required by applicable law or agreed to in writing, software      */
/*distributed under the License is distributed on an "AS IS" BASIS,        */
/*WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. */
/*See the License for the specific language governing permissions and      */
/*limitations under the License.                                           */

#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;

header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}

header ipv4_t {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> totalLen;
    bit<16> identification;
    bit<3>  flags;
    bit<13> fragOffset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdrChecksum;
    bit<32> srcAddr;
    bit<32> dstAddr;
}

struct metadata {
}

struct headers {
    @name(".ethernet") 
    ethernet_t ethernet;
    @name(".ipv4") 
    ipv4_t ipv4;
}

parser ParserImpl(packet_in packet, 
                    out headers hdr, 
                    inout metadata meta,
                    inout standard_metadata_t standard_metadata) {
    
    @name(".start") 
    state start {
        transition parse_ethernet;
    }
    @name(".parse_ethernet") 
    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType) {
            TYPE_IPV4: parse_ipv4;
            default: accept;
        }
    }
    @name(".parse_ipv4") 
    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        transition accept;
    }
}

control egress(inout headers hdr, 
                inout metadata meta, 
                inout standard_metadata_t standard_metadata) {
    apply {
    }
}

control ingress(inout headers hdr, 
                inout metadata meta, 
                inout standard_metadata_t standard_metadata) {
    @name(".fib_hit_nexthop") 
    action fib_hit_nexthop(bit<48> dmac, bit<16> port) {
        hdr.ethernet.dstAddr = dmac;
        standard_metadata.egress_spec = port;
        hdr.ipv4.ttl = hdr.ipv4.ttl + 8w255;
    }

    @name(".on_miss") 
    action on_miss() {
    }

    @name(".rewrite_src_mac") 
    action rewrite_src_mac(bit<48> smac) {
        hdr.ethernet.srcAddr = smac;
    }

    @name(".ipv4_fib_lpm") 
    table ipv4_fib_lpm {
        actions = {
            fib_hit_nexthop;
            on_miss;
        }
        key = {
            hdr.ipv4.dstAddr: lpm;
        }
        size = 512;
    }

    @name(".sendout") 
    table sendout {
        actions = {
            on_miss;
            rewrite_src_mac;
        }
        key = {
            standard_metadata.egress_port: exact;
        }
        size = 512;
    }
    
    apply {
        ipv4_fib_lpm.apply();
        sendout.apply();
    }
}

control DeparserImpl(packet_out packet, in headers hdr) {
    apply {
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
    }
}

control verifyChecksum(inout headers hdr, inout metadata meta) {
    apply {
    }
}

control computeChecksum(inout headers hdr, inout metadata meta) {
    apply {
        update_checksum(
	        hdr.ipv4.isValid(),
            { hdr.ipv4.version,
	          hdr.ipv4.ihl,
              hdr.ipv4.diffserv,
              hdr.ipv4.totalLen,
              hdr.ipv4.identification,
              hdr.ipv4.flags,
              hdr.ipv4.fragOffset,
              hdr.ipv4.ttl,
              hdr.ipv4.protocol,
              hdr.ipv4.srcAddr,
              hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum,
            HashAlgorithm.csum16);
    }
}

V1Switch(ParserImpl(), 
        verifyChecksum(), 
        ingress(), 
        egress(), 
        computeChecksum(), 
        DeparserImpl()
) main;
