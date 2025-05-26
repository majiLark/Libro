;; STAGE 2: ENHANCED LIBRARY MANAGEMENT SYSTEM
;; Added book catalog, due dates, fines, and patron reading lists

;; Enhanced error codes
(define-constant ERR-UNAUTHORIZED u200)
(define-constant ERR-PATRON-EXISTS u201)
(define-constant ERR-PATRON-NOT-FOUND u202)
(define-constant ERR-BOOK-UNAVAILABLE u203)
(define-constant ERR-READING-LIST-FULL u204)
(define-constant ERR-BOOK-NOT-FOUND u205)

;; System limits
(define-constant MAX-READING-LIST-SIZE u20)
(define-constant LOAN-DURATION u1440) ; 24 hours in minutes

;; Enhanced counters
(define-data-var total-patrons uint u0)
(define-data-var total-checkouts uint u0)
(define-data-var total-books uint u0)

;; Enhanced patron registry with reading lists
(define-map patrons principal 
  {
    is-registered: bool,
    card-number: (buff 32),
    join-date: uint,
    total-borrowed: uint,
    outstanding-fines: uint
  }
)

;; Book catalog
(define-map books uint 
  {
    title: (buff 512),
    author: (buff 256),
    isbn: (buff 64),
    is-available: bool,
    added-by: principal,
    total-borrows: uint
  }
)

;; Enhanced checkout records with due dates
(define-map checkouts uint 
  {
    patron: principal,
    book-id: uint,
    checkout-date: uint,
    due-date: uint,
    is-returned: bool,
    fine-amount: uint
  }
)

;; Patron reading lists
(define-map reading-lists principal (list 20 uint))

;; Time utilities
(define-private (current-time)
  (default-to u0 (get-block-info? time u0))
)

(define-private (calculate-due-date (checkout-time uint))
  (+ checkout-time LOAN-DURATION)
)

;; Read-only functions
(define-read-only (is-patron-registered (patron principal))
  (is-some (map-get? patrons patron))
)

(define-read-only (get-patron (patron principal))
  (map-get? patrons patron)
)

(define-read-only (get-book (book-id uint))
  (map-get? books book-id)
)

(define-read-only (get-checkout (checkout-id uint))
  (map-get? checkouts checkout-id)
)

(define-read-only (get-reading-list (patron principal))
  (default-to (list) (map-get? reading-lists patron))
)

(define-read-only (get-system-stats)
  {
    total-patrons: (var-get total-patrons),
    total-checkouts: (var-get total-checkouts),
    total-books: (var-get total-books)
  }
)

;; Register new patron
(define-public (register-patron (card-number (buff 32)))
  (let (
    (patron tx-sender)
    (registration-time (current-time))
  )
    (asserts! (not (is-patron-registered patron)) 
              (err ERR-PATRON-EXISTS))
    
    (map-set patrons patron
      {
        is-registered: true,
        card-number: card-number,
        join-date: registration-time,
        total-borrowed: u0,
        outstanding-fines: u0
      }
    )
    
    ;; Initialize empty reading list
    (map-set reading-lists patron (list))
    
    (var-set total-patrons (+ (var-get total-patrons) u1))
    
    (ok true)
  )
)

;; Add book to catalog
(define-public (add-book (title (buff 512)) (author (buff 256)) (isbn (buff 64)))
  (let (
    (librarian tx-sender)
    (book-id (var-get total-books))
  )
    (asserts! (is-patron-registered librarian) 
              (err ERR-PATRON-NOT-FOUND))
    
    (map-set books book-id
      {
        title: title,
        author: author,
        isbn: isbn,
        is-available: true,
        added-by: librarian,
        total-borrows: u0
      }
    )
    
    (var-set total-books (+ book-id u1))
    
    (ok book-id)
  )
)

;; Checkout a book
(define-public (checkout-book (patron principal) (book-id uint))
  (let (
    (librarian tx-sender)
    (checkout-id (var-get total-checkouts))
    (checkout-time (current-time))
    (due-date (calculate-due-date checkout-time))
    (book-info (unwrap! (get-book book-id) (err ERR-BOOK-NOT-FOUND)))
    (patron-info (unwrap! (get-patron patron) (err ERR-PATRON-NOT-FOUND)))
    (current-reading-list (get-reading-list patron))
  )
    (asserts! (is-patron-registered librarian) 
              (err ERR-PATRON-NOT-FOUND))
    
    (asserts! (get is-available book-info) 
              (err ERR-BOOK-UNAVAILABLE))
    
    (asserts! (< (len current-reading-list) MAX-READING-LIST-SIZE) 
              (err ERR-READING-LIST-FULL))
    
    ;; Create checkout record
    (map-set checkouts checkout-id
      {
        patron: patron,
        book-id: book-id,
        checkout-date: checkout-time,
        due-date: due-date,
        is-returned: false,
        fine-amount: u0
      }
    )
    
    ;; Mark book as unavailable
    (map-set books book-id
      (merge book-info { 
        is-available: false,
        total-borrows: (+ (get total-borrows book-info) u1)
      })
    )
    
    ;; Add to patron's reading list
    (map-set reading-lists patron
      (unwrap-panic (as-max-len? (append current-reading-list checkout-id) u20))
    )
    
    ;; Update patron's borrow count
    (map-set patrons patron
      (merge patron-info { 
        total-borrowed: (+ (get total-borrowed patron-info) u1)
      })
    )
    
    (var-set total-checkouts (+ checkout-id u1))
    
    (ok checkout-id)
  )
)

;; Return a book
(define-public (return-book (checkout-id uint))
  (let (
    (patron tx-sender)
    (checkout-record (unwrap! (get-checkout checkout-id) (err ERR-BOOK-UNAVAILABLE)))
    (book-info (unwrap! (get-book (get book-id checkout-record)) (err ERR-BOOK-NOT-FOUND)))
    (patron-info (unwrap! (get-patron patron) (err ERR-PATRON-NOT-FOUND)))
    (current-time (current-time))
    (due-date (get due-date checkout-record))
    (fine (if (> current-time due-date) (- current-time due-date) u0))
  )
    (asserts! (is-eq (get patron checkout-record) patron) 
              (err ERR-UNAUTHORIZED))
    
    ;; Update checkout record
    (map-set checkouts checkout-id
      (merge checkout-record { 
        is-returned: true,
        fine-amount: fine
      })
    )
    
    ;; Mark book as available
    (map-set books (get book-id checkout-record)
      (merge book-info { is-available: true })
    )
    
    ;; Add fine to patron's account if overdue
    (if (> fine u0)
        (map-set patrons patron
          (merge patron-info { 
            outstanding-fines: (+ (get outstanding-fines patron-info) fine)
          }))
        true)
    
    (ok true)
  )
)

;; Pay fines
(define-public (pay-fine (amount uint))
  (let (
    (patron tx-sender)
    (patron-info (unwrap! (get-patron patron) (err ERR-PATRON-NOT-FOUND)))
    (current-fines (get outstanding-fines patron-info))
  )
    (asserts! (<= amount current-fines) (err ERR-UNAUTHORIZED))
    
    (map-set patrons patron
      (merge patron-info { 
        outstanding-fines: (- current-fines amount)
      })
    )
    
    (ok true)
  )
)

;; Remove book from reading list
(define-public (remove-from-reading-list (checkout-id uint))
  (let (
    (patron tx-sender)
    (current-list (get-reading-list patron))
    (filtered-list (filter (lambda (id) (not (is-eq id checkout-id))) current-list))
  )
    (map-set reading-lists patron filtered-list)
    (ok true)
  )
)