# Recirculation-Digest-TNA-Mechanism


  This P4 program demonstrates:
  1. Packet recirculation using dedicated recirculation ports
  2. Digest emission to control plane for monitoring and learning
  
  Digest Usage:
  - Ingress digest: Sent when packets are recirculated or meet specific criteria
  - Egress digest: Sent when packets exit through monitored ports
  - Control plane can use digest data for:
    * Flow monitoring and analytics
    * Dynamic rule installation
    * Network state learning
    * Anomaly detection
  
  Digest Structure includes:
  - Source and destination IP addresses
  - Ingress/egress port information
  - Recirculation pass count
  - Custom processing fields
  - Timestamp information
 
