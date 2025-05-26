;; STAGE 1: BASIC BOOK MANAGEMENT SYSTEM
;; Simple patron registration and book checkout functionality

;; Basic error codes
(define-constant ERR-UNAUTHORIZED u100)
(define-constant ERR-PATRON-EXISTS u101)
(define-constant ERR-PATRON-NOT-FOUND u102)
(define-constant ERR-BOOK-UNAVAILABLE u103)

;; System counters
(define-data-var total-patrons uint u0)
(define-data-var total-checkouts uint u0)

;; Basic patron registry
(define-map patrons principal 
  {
    is-registered: bool,
    card-number: (buff 32),
    join-date: uint
  }
)

;; Simple checkout tracking
(define-map checkouts uint 
  {
    patron: principal,
    book-title: (buff 256),
    checkout-date: uint,
    is-active: bool
  }
)

;; Get current block time
(define-private (current-time)
  (default-to u0 (get-block-info? time u0))
)

;; Check if patron is registered
(define-read-only (is-patron-registered (patron principal))
  (is-some (map-get? patrons patron))
)

;; Get patron details
(define-read-only (get-patron (patron principal))
  (map-get? patrons patron)
)

;; Get checkout details
(define-read-only (get-checkout (checkout-id uint))
  (map-get? checkouts checkout-id)
)

;; Register new patron
(define-public (register-patron (card-number (buff 32)))
  (let (
    (patron tx-sender)
    (registration-time (current-time))
  )
    ;; Check if patron already registered
    (asserts! (not (is-patron-registered patron)) 
              (err ERR-PATRON-EXISTS))
    
    ;; Register patron
    (map-set patrons patron
      {
        is-registered: true,
        card-number: card-number,
        join-date: registration-time
      }
    )
    
    ;; Update counter
    (var-set total-patrons (+ (var-get total-patrons) u1))
    
    (ok true)
  )
)

;; Checkout a book
(define-public (checkout-book (patron principal) (book-title (buff 256)))
  (let (
    (librarian tx-sender)
    (checkout-id (var-get total-checkouts))
    (checkout-time (current-time))
  )
    ;; Verify librarian is registered
    (asserts! (is-patron-registered librarian) 
              (err ERR-PATRON-NOT-FOUND))
    
    ;; Verify patron is registered
    (asserts! (is-patron-registered patron) 
              (err ERR-PATRON-NOT-FOUND))
    
    ;; Create checkout record
    (map-set checkouts checkout-id
      {
        patron: patron,
        book-title: book-title,
        checkout-date: checkout-time,
        is-active: true
      }
    )
    
    ;; Update counter
    (var-set total-checkouts (+ checkout-id u1))
    
    (ok checkout-id)
  )
)

;; Return a book
(define-public (return-book (checkout-id uint))
  (let (
    (patron tx-sender)
    (checkout-record (unwrap! (get-checkout checkout-id) (err ERR-BOOK-UNAVAILABLE)))
  )
    ;; Verify patron owns this checkout
    (asserts! (is-eq (get patron checkout-record) patron) 
              (err ERR-UNAUTHORIZED))
    
    ;; Mark as returned
    (map-set checkouts checkout-id
      (merge checkout-record { is-active: false })
    )
    
    (ok true)
  )
)

;; Get system statistics
(define-read-only (get-stats)
  {
    total-patrons: (var-get total-patrons),
    total-checkouts: (var-get total-checkouts)
  }
)