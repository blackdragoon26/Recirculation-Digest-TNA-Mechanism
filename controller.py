#!/usr/bin/env python3

import bfrt_grpc.client as gc
import threading
import time

class SimpleController:
    def __init__(self, grpc_addr='localhost:50052', client_id=0, device_id=0):
        # Connect to BFRT
        self.interface = gc.ClientInterface(grpc_addr=grpc_addr, 
                                          client_id=client_id, 
                                          device_id=device_id)
        
        # Get the target and program info
        self.target = gc.Target(device_id=device_id, pipe_id=0xffff)
        self.bfrt_info = self.interface.bfrt_info_get()
        
        # Get table references
        self.my_table = self.bfrt_info.table_get("Ingress.my_table")
        
        # Setup digest handling
        self.setup_digest()
        
    def setup_digest(self):
        """Setup digest reception"""
        try:
            # Get digest table - name might vary based on your P4 program name
            self.digest_table = self.bfrt_info.table_get("pipe.Ingress.digest")
            
            # Enable digest
            self.digest_table.operations_execute(self.target, 'Sync')
            
            # Start digest listener thread
            self.digest_thread = threading.Thread(target=self.digest_listener)
            self.digest_thread.daemon = True
            self.digest_thread.start()
            
            print("Digest setup complete")
            
        except Exception as e:
            print(f"Error setting up digest: {e}")
    
    def digest_listener(self):
        """Listen for digests from the data plane"""
        print("Starting digest listener...")
        
        while True:
            try:
                # Get digest messages
                digest_list = self.digest_table.entry_get(self.target, 
                                                        flags={"from_hw": True}, 
                                                        print_ents=False)
                
                for digest in digest_list:
                    # Extract digest data
                    data = digest.to_dict()
                    
                    src_ip = data['src_ip']
                    dst_ip = data['dst_ip'] 
                    pass_count = data['pass_count']
                    
                    print(f"DIGEST: Flow {self.ip_to_str(src_ip)} -> {self.ip_to_str(dst_ip)}, "
                          f"Pass: {pass_count}")
                    
                    # Process the digest (your logic here)
                    self.process_digest(src_ip, dst_ip, pass_count)
                    
            except Exception as e:
                # No digest available or other error
                time.sleep(0.1)
    
    def process_digest(self, src_ip, dst_ip, pass_count):
        """Process received digest - add your logic here"""
        
        # Example: Install direct forwarding rule after first recirculation
        if pass_count >= 1:
            print(f"Installing direct rule for {self.ip_to_str(src_ip)}")
            
            try:
                # Add table entry to forward directly (port 2) instead of recirculating
                self.my_table.entry_add(
                    self.target,
                    [self.my_table.make_key([gc.KeyTuple('hdr.ipv4.src_addr', src_ip)])],
                    [self.my_table.make_data([gc.DataTuple('port', 2)], 'Ingress.forward')]
                )
                print(f"Rule installed for {self.ip_to_str(src_ip)}")
                
            except Exception as e:
                print(f"Error installing rule: {e}")
    
    def add_recirculation_rule(self, src_ip):
        """Add rule to recirculate packets from specific source"""
        try:
            self.my_table.entry_add(
                self.target,
                [self.my_table.make_key([gc.KeyTuple('hdr.ipv4.src_addr', src_ip)])],
                [self.my_table.make_data([], 'Ingress.recirculate')]
            )
            print(f"Added recirculation rule for {self.ip_to_str(src_ip)}")
            
        except Exception as e:
            print(f"Error adding rule: {e}")
    
    def ip_to_str(self, ip_int):
        """Convert integer IP to string"""
        return f"{(ip_int >> 24) & 0xFF}.{(ip_int >> 16) & 0xFF}.{(ip_int >> 8) & 0xFF}.{ip_int & 0xFF}"
    
    def str_to_ip(self, ip_str):
        """Convert string IP to integer"""
        parts = ip_str.split('.')
        return (int(parts[0]) << 24) + (int(parts[1]) << 16) + (int(parts[2]) << 8) + int(parts[3])

def main():
    # Create controller
    controller = SimpleController()
    
    print("Controller started. Setting up initial rules...")
    
    # Add some test rules to trigger recirculation
    test_ips = ["10.0.0.1", "10.0.0.2", "192.168.1.1"]
    
    for ip_str in test_ips:
        controller.add_recirculation_rule(controller.str_to_ip(ip_str))
    
    print("Initial rules added. Listening for digests...")
    print("Press Ctrl+C to exit")
    
    try:
        # Keep the main thread alive
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\nShutting down controller...")

if __name__ == "__main__":
    main()
