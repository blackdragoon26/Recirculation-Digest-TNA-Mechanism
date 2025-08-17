#include <core.p4>
#include <tna.p4>

header ethernet_h {
    bit<48> dst_addr;
    bit<48> src_addr;
    bit<16> ether_type;
}

header ipv4_h {
    bit<4>  version;
    bit<4>  ihl;
    bit<8>  diffserv;
    bit<16> total_len;
    bit<16> identification;
    bit<3>  flags;
    bit<13> frag_offset;
    bit<8>  ttl;
    bit<8>  protocol;
    bit<16> hdr_checksum;
    bit<32> src_addr;
    bit<32> dst_addr;
}

struct header_t {
    ethernet_h ethernet;
    ipv4_h     ipv4;
}

struct ig_metadata_t {
    bit<8> pass_count;
}

struct eg_metadata_t {
    bit<8> dummy;
}

parser IngressParser(
    packet_in pkt,
    out header_t hdr,
    out ig_metadata_t ig_md,
    out ingress_intrinsic_metadata_t ig_intr_md) {
    
    state start {
        pkt.extract(ig_intr_md);
        ig_md.pass_count = 0;
        
        // Check if packet came from recirculation port 68
        transition select(ig_intr_md.ingress_port) {
            68: recirculated_packet;
            default: parse_ethernet;
        }
    }
    
    state recirculated_packet {
        // This is a recirculated packet - increment pass count
        ig_md.pass_count = 1;
        transition parse_ethernet;
    }
    
    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

control Ingress(
    inout header_t hdr,
    inout ig_metadata_t ig_md,
    in ingress_intrinsic_metadata_t ig_intr_md,
    in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
    inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
    inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {

    action recirculate() {
        // Send to recirculation port 68
        ig_tm_md.ucast_egress_port = 68;
    }
    
    action forward(bit<9> port) {
        ig_tm_md.ucast_egress_port = port;
    }
    
    table my_table {
        key = {
            hdr.ipv4.src_addr: exact;
        }
        actions = {
            recirculate;
            forward;
        }
        default_action = forward(1);
        size = 1024;
    }
    
    apply {
        if (hdr.ipv4.isValid()) {
            // Only recirculate if it's the first pass
            if (ig_md.pass_count == 0) {
                my_table.apply();
            } else {
                // Already recirculated once, just forward
                forward(1);
            }
        }
    }
}

control IngressDeparser(
    packet_out pkt,
    inout header_t hdr,
    in ig_metadata_t ig_md,
    in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {
    
    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
    }
}

parser EgressParser(
    packet_in pkt,
    out header_t hdr,
    out eg_metadata_t eg_md,
    out egress_intrinsic_metadata_t eg_intr_md) {
    
    state start {
        pkt.extract(eg_intr_md);
        eg_md.dummy = 0;
        transition parse_ethernet;
    }
    
    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            0x0800: parse_ipv4;
            default: accept;
        }
    }
    
    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition accept;
    }
}

control Egress(
    inout header_t hdr,
    inout eg_metadata_t eg_md,
    in egress_intrinsic_metadata_t eg_intr_md,
    in egress_intrinsic_metadata_from_parser_t eg_prsr_md,
    inout egress_intrinsic_metadata_for_deparser_t eg_dprsr_md,
    inout egress_intrinsic_metadata_for_output_port_t eg_oport_md) {
    
    apply {
        // Basic egress - no digest for now
    }
}

control EgressDeparser(
    packet_out pkt,
    inout header_t hdr,
    in eg_metadata_t eg_md,
    in egress_intrinsic_metadata_for_deparser_t eg_dprsr_md) {
    
    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.ipv4);
    }
}

Pipeline(
    IngressParser(),
    Ingress(),
    IngressDeparser(),
    EgressParser(),
    Egress(),
    EgressDeparser()
) pipe;

Switch(pipe) main;