# Distributed Cloud Database Architecture Strategy
**Course:** MIT 8103 Advanced Database Systems  
**Case Study:** ApexPay Bank / Fintech Platform  
**Student Name:** Ifenna Victor Okany | ID: 301923302  

---

## 1. Multi-Region Replication Architecture
- **In-Region Synchronous Replication:** Write-Ahead Log (WAL) records are written to a synchronous standby before confirming commit, guaranteeing $\text{RPO} = 0$ (Zero data loss).
- **Automated Failover:** Orchestrated via Patroni with Raft/etcd consensus, achieving $\text{RTO} < 15 \text{ seconds}$.
- **Cross-Region Asynchronous Standby:** Streams data continuously to a disaster recovery region for business continuity.

---

## 2. Horizontal Sharding Strategy
- **Partition Key:** `customer_id` (UUID).
- **Locality Benefit:** Placing all accounts and transactions for a customer on the same physical shard ensures over **95% of transactions are Single-Shard**, avoiding expensive distributed Two-Phase Commit (2PC) network latency.

---

## 3. PACELC Theorem Mapping
- **Core Banking Ledger:** **PC/EC** (Prioritizes Consistency during a network partition, and Consistency over latency during normal operations).
- **Push Notifications:** **PA/EL** (Prioritizes Availability and low latency over immediate global consistency).
