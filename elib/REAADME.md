# 📘 Libro - Digital Archive System

**Libro** is a decentralized smart contract system built to manage a comprehensive digital reading platform. It provides support for patron enrollment, publication cataloging, book checkout and return processes, wishlist management, hold queueing, and penalty enforcement. Libro is designed for transparency, efficiency, and decentralized control in managing digital publications.

---

## 🚀 Features

- 📖 **Patron Enrollment**  
  Enroll and manage user accounts with status, access levels, and penalty tracking.

- 📚 **Publication Cataloging**  
  Add and manage digital publications with metadata and availability flags.

- 🔄 **Checkout and Return System**  
  Issue and return books with automatic penalty calculation for overdue returns.

- ❤️ **Wishlist Management**  
  Patrons can maintain a wishlist of desired publications (max 25 items).

- ⏳ **Hold Queue System**  
  Users can place holds on currently unavailable publications (max 10 holds).

- 💸 **Penalty System**  
  Automatic penalty tracking for late returns with support for partial or full settlement.

- 📊 **Platform Analytics**  
  View key system metrics and activity summaries for patrons.

---

## 🛠 Contract Constants

- `WISHLIST-MAX-SIZE`: `25`
- `HOLD-REQUEST-LIMIT`: `10`
- `LOAN-PERIOD-MAX`: `2160` blocks
- `PUBLICATION-TITLE-MAX`: `1024` bytes

---

## 📦 Data Models

- `archive-patrons`: Patron account information
- `publication-catalog`: Registered publications
- `checkout-records`: Active and archived checkout logs
- `patron-wishlists`: Wishlist entries per user
- `hold-queue`: Hold requests on unavailable publications
- `patron-holds`: Active holds by patron

---

## 🔐 Error Codes

- `u300`: Unauthorized access  
- `u301`: Patron already exists  
- `u302`: Patron not found  
- `u303`: Publication unavailable  
- `u304`: Wishlist limit reached  
- `u305`: Publication already in use  
- `u306`: Hold limit exceeded

---

## 📘 Key Functions

### ✅ Public

- `enroll-patron`
- `catalog-publication`
- `issue-checkout`
- `complete-checkout`
- `place-hold`
- `remove-checkout-record`
- `settle-penalties`
- `refresh-patron-card`

### 🔎 Read-Only

- `fetch-patron-info`
- `fetch-publication-info`
- `fetch-checkout-record`
- `patron-activity-summary`
- `system-status-report`

---

## 🔧 Developer Notes

- Time is derived using `(get-block-info? time u0)`, which ensures timestamp precision.
- All lists use `as-max-len?` to strictly enforce limits defined by platform constants.
- Only patrons registered in `archive-patrons` are allowed to interact with the system.
- Checkout IDs and Hold IDs increment through global counters to ensure uniqueness.


