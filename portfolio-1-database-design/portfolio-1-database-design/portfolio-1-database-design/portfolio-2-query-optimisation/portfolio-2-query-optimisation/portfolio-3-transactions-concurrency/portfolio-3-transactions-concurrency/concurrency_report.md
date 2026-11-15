# Concurrency Control, Isolation Levels & Race Conditions
**Course:** MIT 8103 Advanced Database Systems  
**Case Study:** ApexPay Bank / Fintech Platform  
**Student Name:** Ifenna Victor Okany | ID: 301923302  

---

## 1. ANSI SQL Isolation Levels Analysis

| Isolation Level | Dirty Reads | Non-Repeatable Read | Phantom Read |
| :--- | :--- | :--- | :--- |
| **Read Uncommitted** | Permitted | Permitted | Permitted |
| **Read Committed** (Default) | Prevented | Permitted | Permitted |
| **Repeatable Read** | Prevented | Prevented | Prevented (Snapshot) |
| **Serializable** | Prevented | Prevented | Prevented |

---

## 2. Race Conditions & The Double-Spend Problem
In a fintech platform, if a customer with a ₦100,000 balance issues two simultaneous transfers of ₦80,000:
1. Without locking, both transactions check the balance at the same time: ₦100,000 $\ge$ ₦80,000 (Approved).
2. Both deduct ₦80,000, sending out ₦160,000 when only ₦100,000 existed.

### The Solution:
Pessimistic Row-Level Locking (`SELECT available_balance FROM accounts WHERE account_id = ... FOR UPDATE`).
The second transaction is forced to wait until the first completes. When it reads the updated balance of ₦20,000, it rejects the second transfer for insufficient funds.

---

## 3. Eliminating Deadlocks Mathematically
When Account A transfers to Account B while Account B simultaneously transfers to Account A, inverted lock requests cause deadlocks ($A \to B \to A$).

### The Solution:
In `sp_execute_p2p_transfer`, locks are requested in strict ascending order of account UUIDs:
$$\text{Lock Order} = \min(\text{ID}_1, \text{ID}_2) \quad \text{then} \quad \max(\text{ID}_1, \text{ID}_2)$$
Because all transactions acquire locks in identical order, cyclic deadlocks are mathematically impossible.
