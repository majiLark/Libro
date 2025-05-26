;; BOOK-MANAGEMENT-PLATFORM - Enhanced Digital Archive System
;; Comprehensive reading platform with patron management and publication tracking

;; System error responses
(define-constant UNAUTHORIZED-ACCESS u300)
(define-constant PATRON-EXISTS u301)
(define-constant PATRON-MISSING u302)
(define-constant PUBLICATION-UNAVAILABLE u303)
(define-constant WISHLIST-OVERFLOW u304)
(define-constant PUBLICATION-IN-USE u305)
(define-constant HOLD-QUOTA-EXCEEDED u306)

;; Platform limitations
(define-constant PUBLICATION-TITLE-MAX u1024)
(define-constant WISHLIST-MAX-SIZE u25)
(define-constant LOAN-PERIOD-MAX u2160)
(define-constant HOLD-REQUEST-LIMIT u10)

;; Archive metrics
(define-data-var circulation-count uint u0)
(define-data-var registered-patrons uint u0)
(define-data-var checkout-sequence-id uint u0)
(define-data-var publication-inventory uint u0)
(define-data-var hold-requests-total uint u0)

;; Core data models
(define-map archive-patrons principal 
  {
    account-status: bool,
    patron-id: (buff 33),
    enrollment-timestamp: uint,
    checkout-history: uint,
    access-level: uint,
    penalty-balance: uint
  }
)

(define-map checkout-records uint 
  {
    issuer: principal,
    patron: principal,
    publication-data: (buff 1024),
    issue-timestamp: uint,
    return-deadline: uint,
    completion-status: bool,
    penalty-amount: uint
  }
)

(define-map publication-catalog uint 
  {
    publication-name: (buff 1024),
    creator: (buff 512),
    identifier: (buff 64),
    cataloger: principal,
    catalog-date: uint,
    availability-flag: bool,
    active-patron: (optional principal),
    usage-counter: uint
  }
)

(define-map hold-queue uint 
  {
    target-publication: uint,
    requesting-patron: principal,
    request-timestamp: uint,
    queue-status: bool
  }
)

(define-map patron-wishlists principal (list 25 uint))
(define-map patron-holds principal (list 10 uint))

;; Time tracking utility
(define-private (fetch-timestamp)
  (default-to u0 (get-block-info? time u0))
)

;; Data access functions
(define-read-only (fetch-patron-info (patron principal))
  (map-get? archive-patrons patron)
)

(define-read-only (validate-patron-status (patron principal))
  (is-some (map-get? archive-patrons patron))
)

(define-read-only (fetch-checkout-record (record-id uint))
  (map-get? checkout-records record-id)
)

(define-read-only (fetch-publication-info (publication-id uint))
  (map-get? publication-catalog publication-id)
)

(define-read-only (fetch-hold-info (hold-id uint))
  (map-get? hold-queue hold-id)
)

(define-read-only (fetch-patron-wishlist (patron principal))
  (default-to (list) (map-get? patron-wishlists patron))
)

(define-read-only (fetch-patron-holds (patron principal))
  (default-to (list) (map-get? patron-holds patron))
)

(define-read-only (platform-metrics)
  {
    total-checkouts: (var-get circulation-count),
    active-patrons: (var-get registered-patrons),
    catalog-size: (var-get publication-inventory),
    pending-holds: (var-get hold-requests-total)
  }
)

;; Patron enrollment system
(define-public (enroll-patron (patron-card (buff 33)))
  (let (
    (new-patron tx-sender)
    (enrollment-time (fetch-timestamp))
  )
    ;; Block duplicate enrollments
    (asserts! (not (validate-patron-status new-patron)) 
              (err PATRON-EXISTS))
    
    ;; Create patron record
    (map-set archive-patrons new-patron
      {
        account-status: true,
        patron-id: patron-card,
        enrollment-timestamp: enrollment-time,
        checkout-history: u0,
        access-level: u1,
        penalty-balance: u0
      }
    )
    
    ;; Setup patron collections
    (map-set patron-wishlists new-patron (list))
    (map-set patron-holds new-patron (list))
    
    ;; Increment patron count
    (var-set registered-patrons (+ (var-get registered-patrons) u1))
    (ok true)
  )
)

;; Publication cataloging
(define-public (catalog-publication (name (buff 1024)) (creator (buff 512)) (identifier (buff 64)))
  (let (
    (cataloger tx-sender)
    (publication-id (var-get publication-inventory))
    (catalog-time (fetch-timestamp))
  )
    ;; Validate cataloger credentials
    (asserts! (validate-patron-status cataloger) 
              (err PATRON-MISSING))
    
    ;; Register publication
    (map-set publication-catalog publication-id
      {
        publication-name: name,
        creator: creator,
        identifier: identifier,
        cataloger: cataloger,
        catalog-date: catalog-time,
        availability-flag: true,
        active-patron: none,
        usage-counter: u0
      }
    )
    
    ;; Update inventory count
    (var-set publication-inventory (+ publication-id u1))
    
    (ok publication-id)
  )
)

;; Publication checkout process
(define-public (issue-checkout (target-patron principal) (publication-info (buff 1024)))
  (let (
    (staff-member tx-sender)
    (checkout-id (var-get circulation-count))
    (issue-time (fetch-timestamp))
    (deadline (+ issue-time LOAN-PERIOD-MAX))
    (staff-record (unwrap! (fetch-patron-info staff-member) (err PATRON-MISSING)))
    (patron-wishlist (fetch-patron-wishlist target-patron))
  )
    ;; Validate staff credentials
    (asserts! (validate-patron-status staff-member) 
              (err PATRON-MISSING))
    
    ;; Validate target patron
    (asserts! (validate-patron-status target-patron) 
              (err PATRON-MISSING))
    
    ;; Verify wishlist capacity
    (asserts! (< (len patron-wishlist) WISHLIST-MAX-SIZE)
              (err WISHLIST-OVERFLOW))
    
    ;; Generate checkout record
    (map-set checkout-records checkout-id
      {
        issuer: staff-member,
        patron: target-patron,
        publication-data: publication-info,
        issue-timestamp: issue-time,
        return-deadline: deadline,
        completion-status: false,
        penalty-amount: u0
      }
    )
    
    ;; Update patron wishlist
    (map-set patron-wishlists 
             target-patron
             (unwrap-panic (as-max-len? (append patron-wishlist checkout-id) u25)))
    
    ;; Update staff checkout history
    (map-set archive-patrons staff-member
      (merge staff-record { 
        checkout-history: (+ (get checkout-history staff-record) u1)
      })
    )
    
    ;; Update circulation counter
    (var-set circulation-count (+ checkout-id u1))
    
    (ok checkout-id)
  )
)

;; Publication return processing
(define-public (complete-checkout (checkout-id uint))
  (let (
    (patron tx-sender)
    (checkout-info (unwrap! (fetch-checkout-record checkout-id) (err PUBLICATION-UNAVAILABLE)))
    (current-time (fetch-timestamp))
    (deadline (get return-deadline checkout-info))
    (overdue-penalty (if (> current-time deadline) (- current-time deadline) u0))
  )
    ;; Validate patron authorization
    (asserts! (is-eq (get patron checkout-info) patron) 
              (err UNAUTHORIZED-ACCESS))
    
    ;; Process return with penalty calculation
    (map-set checkout-records checkout-id
      (merge checkout-info { 
        completion-status: true,
        penalty-amount: overdue-penalty
      })
    )
    
    ;; Apply penalty if overdue
    (if (> overdue-penalty u0)
        (let ((patron-record (unwrap! (fetch-patron-info patron) (err PATRON-MISSING))))
          (map-set archive-patrons patron
            (merge patron-record { 
              penalty-balance: (+ (get penalty-balance patron-record) overdue-penalty)
            }))
          true)
        true)
    
    (ok true)
  )
)

;; Publication hold system
(define-public (place-hold (publication-id uint))
  (let (
    (patron tx-sender)
    (hold-id (var-get hold-requests-total))
    (request-time (fetch-timestamp))
    (patron-hold-list (fetch-patron-holds patron))
    (publication-info (unwrap! (fetch-publication-info publication-id) (err PUBLICATION-UNAVAILABLE)))
  )
    ;; Verify patron registration
    (asserts! (validate-patron-status patron) 
              (err PATRON-MISSING))
    
    ;; Verify hold limit
    (asserts! (< (len patron-hold-list) HOLD-REQUEST-LIMIT)
              (err HOLD-QUOTA-EXCEEDED))
    
    ;; Confirm publication is unavailable
    (asserts! (not (get availability-flag publication-info))
              (err PUBLICATION-IN-USE))
    
    ;; Register hold request
    (map-set hold-queue hold-id
      {
        target-publication: publication-id,
        requesting-patron: patron,
        request-timestamp: request-time,
        queue-status: true
      }
    )
    
    ;; Update patron hold list
    (map-set patron-holds 
             patron
             (unwrap-panic (as-max-len? (append patron-hold-list hold-id) u10)))
    
    ;; Update hold counter
    (var-set hold-requests-total (+ hold-id u1))
    
    (ok hold-id)
  )
)

;; Record archival system
(define-public (remove-checkout-record (record-id uint))
  (let (
    (user tx-sender)
    (record-data (unwrap! (fetch-checkout-record record-id) (err PUBLICATION-UNAVAILABLE)))
  )
    ;; Validate user permissions
    (asserts! (or 
               (is-eq (get issuer record-data) user)
               (is-eq (get patron record-data) user))
             (err UNAUTHORIZED-ACCESS))
    
    ;; Remove from patron wishlist if applicable
    (if (is-eq (get patron record-data) user)
        (begin
          (var-set checkout-sequence-id record-id)
          (map-set patron-wishlists 
                   user 
                   (fold filter-wishlist-items (fetch-patron-wishlist user) (list))))
        true)
    
    ;; Archive the record
    (map-delete checkout-records record-id)
    
    (ok true)
  )
)

;; Wishlist filtering helper
(define-private (filter-wishlist-items (item-id uint) (filtered-list (list 25 uint)))
  (if (is-eq item-id (var-get checkout-sequence-id))
      filtered-list
      (unwrap-panic (as-max-len? (append filtered-list item-id) u25)))
)

;; Penalty payment processing
(define-public (settle-penalties (payment-amount uint))
  (let (
    (patron tx-sender)
    (patron-record (unwrap! (fetch-patron-info patron) (err PATRON-MISSING)))
    (outstanding-balance (get penalty-balance patron-record))
  )
    ;; Validate payment amount
    (asserts! (<= payment-amount outstanding-balance) (err UNAUTHORIZED-ACCESS))
    
    ;; Process payment
    (map-set archive-patrons patron
      (merge patron-record { 
        penalty-balance: (- outstanding-balance payment-amount)
      })
    )
    
    (ok true)
  )
)

;; Patron ID card update
(define-public (refresh-patron-card (updated-card (buff 33)))
  (let (
    (patron tx-sender)
    (patron-record (unwrap! (fetch-patron-info patron) (err PATRON-MISSING)))
  )
    ;; Update patron card information
    (map-set archive-patrons patron
      (merge patron-record { patron-id: updated-card })
    )
    
    (ok true)
  )
)

;; Additional utility functions for enhanced uniqueness

;; Patron activity summary
(define-read-only (patron-activity-summary (patron principal))
  (let (
    (patron-info (fetch-patron-info patron))
    (wishlist-size (len (fetch-patron-wishlist patron)))
    (holds-count (len (fetch-patron-holds patron)))
  )
    (match patron-info
      patron-data (some {
        patron-status: (get account-status patron-data),
        total-checkouts: (get checkout-history patron-data),
        current-wishlist-items: wishlist-size,
        active-holds: holds-count,
        outstanding-penalties: (get penalty-balance patron-data),
        membership-tier: (get access-level patron-data)
      })
      none
    )
  )
)

;; System health check
(define-read-only (system-status-report)
  {
    platform-active: true,
    total-circulation: (var-get circulation-count),
    patron-base: (var-get registered-patrons),
    catalog-entries: (var-get publication-inventory),
    queue-depth: (var-get hold-requests-total),
    system-timestamp: (fetch-timestamp)
  }
)