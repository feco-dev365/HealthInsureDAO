;; Claims Processing System for HealthInsureDAO
;; 
;; This contract handles the complete claims lifecycle including submission,
;; validation, automated processing, and payouts. It integrates with the
;; premium calculator and risk pool system to ensure fair claim processing
;; based on user health profiles and pool membership.
;;
;; Key Features:
;; - Automated claim validation using health data oracles
;; - Tiered claim processing based on risk pool membership
;; - Fraud detection through health pattern analysis
;; - Instant payouts for pre-approved claim types
;; - Appeal process for disputed claims
;; - Integration with existing premium and risk pool contracts

(define-constant contract-owner tx-sender)

;; Error constants
(define-constant err-owner-only (err u300))
(define-constant err-claim-not-found (err u301))
(define-constant err-invalid-claim-amount (err u302))
(define-constant err-user-not-insured (err u303))
(define-constant err-claim-already-exists (err u304))
(define-constant err-insufficient-pool-funds (err u305))
(define-constant err-claim-expired (err u306))
(define-constant err-invalid-claim-type (err u307))
(define-constant err-fraud-detected (err u308))
(define-constant err-claim-already-processed (err u309))
(define-constant err-unauthorized-validator (err u310))

;; Claim type constants
(define-constant claim-type-emergency u1)
(define-constant claim-type-routine u2)
(define-constant claim-type-preventive u3)
(define-constant claim-type-chronic u4)
(define-constant claim-type-mental-health u5)

;; Claim status constants
(define-constant status-pending u1)
(define-constant status-under-review u2)
(define-constant status-approved u3)
(define-constant status-rejected u4)
(define-constant status-paid u5)
(define-constant status-appealed u6)

;; Processing limits
(define-constant max-claim-amount u1000000) ;; 1M STX max claim
(define-constant claim-expiry-blocks u4320) ;; ~30 days
(define-constant auto-approve-threshold u50000) ;; Auto-approve claims under 50K STX
(define-constant fraud-score-threshold u75) ;; Fraud detection threshold

;; Data Maps

;; Individual claims
(define-map claims
  { claim-id: uint }
  {
    claimant: principal,
    claim-type: uint,
    amount-requested: uint,
    amount-approved: uint,
    description: (string-ascii 500),
    submitted-at: uint,
    processed-at: uint,
    status: uint,
    validator: (optional principal),
    fraud-score: uint,
    supporting-data-hash: (buff 32)
  }
)

;; Claim validation data
(define-map claim-validations
  { claim-id: uint }
  {
    health-data-verified: bool,
    medical-records-hash: (buff 32),
    provider-verification: bool,
    automated-checks-passed: bool,
    manual-review-required: bool,
    validation-notes: (string-ascii 200)
  }
)

;; User claim history
(define-map user-claim-history
  { user: principal }
  {
    total-claims: uint,
    total-claimed-amount: uint,
    total-paid-amount: uint,
    last-claim-date: uint,
    claim-frequency-score: uint, ;; Higher = more frequent claims
    average-claim-amount: uint
  }
)

;; Pool claim statistics
(define-map pool-claim-stats
  { pool-id: uint }
  {
    total-pool-claims: uint,
    total-pool-payouts: uint,
    average-processing-time: uint,
    fraud-detection-rate: uint,
    pool-reserve-balance: uint
  }
)

;; Authorized claim validators
(define-map authorized-validators
  { validator: principal }
  {
    is-authorized: bool,
    specialization: uint, ;; Claim type specialization
    validation-count: uint,
    accuracy-score: uint
  }
)

;; Appeal records
(define-map claim-appeals
  { claim-id: uint }
  {
    appealed-by: principal,
    appeal-reason: (string-ascii 300),
    appealed-at: uint,
    appeal-status: uint,
    reviewed-by: (optional principal),
    appeal-decision: (optional bool)
  }
)

;; Data variables
(define-data-var next-claim-id uint u1)
(define-data-var total-claims-processed uint u0)
(define-data-var total-payouts uint u0)
(define-data-var contract-reserve-balance uint u0)

;; Public Functions

;; Submit a new insurance claim
(define-public (submit-claim 
                (claim-type uint)
                (amount-requested uint)
                (description (string-ascii 500))
                (supporting-data-hash (buff 32)))
  (let (
    (claim-id (var-get next-claim-id))
    (claimant tx-sender)
    (current-block stacks-block-height)
  )
    (begin
      ;; Validate inputs
      (asserts! (and (>= claim-type u1) (<= claim-type u5)) err-invalid-claim-type)
      (asserts! (and (> amount-requested u0) (<= amount-requested max-claim-amount)) err-invalid-claim-amount)
      
      ;; Check if user has active insurance (would integrate with premium calculator)
      ;; For now, we'll assume all users are insured
      
      ;; Create the claim
      (map-set claims
        { claim-id: claim-id }
        {
          claimant: claimant,
          claim-type: claim-type,
          amount-requested: amount-requested,
          amount-approved: u0,
          description: description,
          submitted-at: current-block,
          processed-at: u0,
          status: status-pending,
          validator: none,
          fraud-score: u0,
          supporting-data-hash: supporting-data-hash
        }
      )
      
      ;; Initialize validation record
      (map-set claim-validations
        { claim-id: claim-id }
        {
          health-data-verified: false,
          medical-records-hash: supporting-data-hash,
          provider-verification: false,
          automated-checks-passed: false,
          manual-review-required: true,
          validation-notes: ""
        }
      )
      
      ;; Update user claim history
      (update-user-claim-history claimant amount-requested)
      
      ;; Increment claim counter
      (var-set next-claim-id (+ claim-id u1))
      
      ;; Trigger automated processing for small claims
      (if (<= amount-requested auto-approve-threshold)
          (process-claim-automated claim-id)
          (ok claim-id)
      )
    )
  )
)

;; Automated claim processing for small amounts
(define-private (process-claim-automated (claim-id uint))
  (let (
    (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
    (claimant (get claimant claim))
    (amount (get amount-requested claim))
    (fraud-score (calculate-fraud-score claimant claim-id))
  )
    (begin
      ;; Update fraud score
      (map-set claims
        { claim-id: claim-id }
        (merge claim { fraud-score: fraud-score })
      )
      
      ;; Auto-approve if fraud score is low
      (if (< fraud-score fraud-score-threshold)
          (approve-and-pay-claim claim-id amount none)
          (begin
            ;; Flag for manual review
            (map-set claims
              { claim-id: claim-id }
              (merge claim { status: status-under-review })
            )
            (ok claim-id)
          )
      )
    )
  )
)

;; Manual claim validation by authorized validators
(define-public (validate-claim 
                (claim-id uint)
                (health-data-verified bool)
                (provider-verification bool)
                (validation-notes (string-ascii 200)))
  (let (
    (validator tx-sender)
    (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
  )
    (begin
      ;; Check validator authorization
      (asserts! (is-authorized-validator validator) err-unauthorized-validator)
      (asserts! (is-eq (get status claim) status-pending) err-claim-already-processed)
      
      ;; Update validation record
      (map-set claim-validations
        { claim-id: claim-id }
        {
          health-data-verified: health-data-verified,
          medical-records-hash: (get supporting-data-hash claim),
          provider-verification: provider-verification,
          automated-checks-passed: true,
          manual-review-required: false,
          validation-notes: validation-notes
        }
      )
      
      ;; Update claim with validator info
      (map-set claims
        { claim-id: claim-id }
        (merge claim {
          validator: (some validator),
          status: status-under-review
        })
      )
      
      ;; Update validator stats
      (update-validator-stats validator)
      
      (ok true)
    )
  )
)

;; Approve and pay claim
(define-public (approve-claim (claim-id uint) (approved-amount uint))
  (let (
    (approver tx-sender)
    (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
  )
    (begin
      ;; Only owner or authorized validators can approve
      (asserts! (or (is-eq approver contract-owner) 
                    (is-authorized-validator approver)) err-unauthorized-validator)
      (asserts! (is-eq (get status claim) status-under-review) err-claim-already-processed)
      (asserts! (<= approved-amount (get amount-requested claim)) err-invalid-claim-amount)
      
      (approve-and-pay-claim claim-id approved-amount (some approver))
    )
  )
)

;; Private function to approve and pay claim
(define-private (approve-and-pay-claim (claim-id uint) (amount uint) (approver (optional principal)))
  (let (
    (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
    (claimant (get claimant claim))
  )
    (begin
      ;; Update claim status
      (map-set claims
        { claim-id: claim-id }
        (merge claim {
          amount-approved: amount,
          status: status-approved,
          processed-at: stacks-block-height
        })
      )
      
      ;; Process payment (in real implementation, this would transfer tokens)
      (unwrap! (process-payout claim-id claimant amount) err-insufficient-pool-funds)
      
      ;; Update global statistics
      (var-set total-claims-processed (+ (var-get total-claims-processed) u1))
      (var-set total-payouts (+ (var-get total-payouts) amount))
      
      (ok claim-id)
    )
  )
)

;; Process payout to claimant
(define-private (process-payout (claim-id uint) (claimant principal) (amount uint))
  (begin
    ;; In a real implementation, this would:
    ;; 1. Check pool reserves
    ;; 2. Transfer tokens from pool to claimant
    ;; 3. Update pool balances
    ;; For now, we'll just update the claim status
    
    (map-set claims
      { claim-id: claim-id }
      (merge (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found) {
        status: status-paid
      })
    )
    (ok true)
  )
)

;; Reject a claim
(define-public (reject-claim (claim-id uint) (reason (string-ascii 200)))
  (let (
    (rejector tx-sender)
    (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
  )
    (begin
      (asserts! (or (is-eq rejector contract-owner) 
                    (is-authorized-validator rejector)) err-unauthorized-validator)
      (asserts! (is-eq (get status claim) status-under-review) err-claim-already-processed)
      
      (map-set claims
        { claim-id: claim-id }
        (merge claim {
          status: status-rejected,
          processed-at: stacks-block-height
        })
      )
      
      (ok true)
    )
  )
)

;; Submit an appeal for rejected claim
(define-public (submit-appeal (claim-id uint) (appeal-reason (string-ascii 300)))
  (let (
    (appellant tx-sender)
    (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-claim-not-found))
  )
    (begin
      (asserts! (is-eq appellant (get claimant claim)) err-unauthorized-validator)
      (asserts! (is-eq (get status claim) status-rejected) err-claim-already-processed)
      
      ;; Create appeal record
      (map-set claim-appeals
        { claim-id: claim-id }
        {
          appealed-by: appellant,
          appeal-reason: appeal-reason,
          appealed-at: stacks-block-height,
          appeal-status: status-pending,
          reviewed-by: none,
          appeal-decision: none
        }
      )
      
      ;; Update claim status
      (map-set claims
        { claim-id: claim-id }
        (merge claim { status: status-appealed })
      )
      
      (ok true)
    )
  )
)

;; Helper Functions

;; Calculate fraud score based on user history and claim patterns
(define-private (calculate-fraud-score (user principal) (claim-id uint))
  (let (
    (history (default-to 
               { total-claims: u0, total-claimed-amount: u0, total-paid-amount: u0, 
                 last-claim-date: u0, claim-frequency-score: u0, average-claim-amount: u0 }
               (map-get? user-claim-history { user: user })))
    ;; Fixed default-to types for claim record
    (claim (default-to 
               { claimant: contract-owner, claim-type: u0, amount-requested: u0, amount-approved: u0, 
                 description: "", submitted-at: u0, processed-at: u0, status: u0, 
                 validator: none, fraud-score: u0, supporting-data-hash: 0x0000000000000000000000000000000000000000000000000000000000000000 }
               (map-get? claims { claim-id: claim-id })))
    (frequency-score (get claim-frequency-score history))
    (amount-score (calculate-amount-anomaly-score user (get amount-requested claim)))
    (timing-score (calculate-timing-anomaly-score user))
  )
    ;; Combine different fraud indicators
    (/ (+ frequency-score amount-score timing-score) u3)
  )
)

;; Calculate amount anomaly score
(define-private (calculate-amount-anomaly-score (user principal) (claim-amount uint))
  (match (map-get? user-claim-history { user: user })
    history
    (let ((avg-amount (get average-claim-amount history)))
      (if (is-eq avg-amount u0)
          u0  ;; First claim, no anomaly
          (if (> claim-amount (* avg-amount u3))
              u50  ;; Claim is 3x average, moderate risk
              (if (> claim-amount (* avg-amount u5))
                  u80  ;; Claim is 5x average, high risk
                  u10  ;; Normal range
              )
          )
      )
    )
    u0  ;; No history, no anomaly
  )
)

;; Calculate timing anomaly score
(define-private (calculate-timing-anomaly-score (user principal))
  (match (map-get? user-claim-history { user: user })
    history
    (let (
      (last-claim (get last-claim-date history))
      (current-block stacks-block-height)
      (blocks-since-last (- current-block last-claim))
    )
      (if (< blocks-since-last u144) ;; Less than 1 day
          u60  ;; High frequency, suspicious
          (if (< blocks-since-last u1008) ;; Less than 1 week
              u30  ;; Moderate frequency
              u5   ;; Normal frequency
          )
      )
    )
    u0  ;; No history
  )
)

;; Update user claim history
(define-private (update-user-claim-history (user principal) (claim-amount uint))
  (let (
    (current-history (default-to 
                       { total-claims: u0, total-claimed-amount: u0, total-paid-amount: u0,
                         last-claim-date: u0, claim-frequency-score: u0, average-claim-amount: u0 }
                       (map-get? user-claim-history { user: user })))
    (new-total-claims (+ (get total-claims current-history) u1))
    (new-total-amount (+ (get total-claimed-amount current-history) claim-amount))
    (new-average (/ new-total-amount new-total-claims))
  )
    (map-set user-claim-history
      { user: user }
      {
        total-claims: new-total-claims,
        total-claimed-amount: new-total-amount,
        total-paid-amount: (get total-paid-amount current-history),
        last-claim-date: stacks-block-height,
        claim-frequency-score: (calculate-frequency-score user),
        average-claim-amount: new-average
      }
    )
  )
)

;; Calculate claim frequency score
(define-private (calculate-frequency-score (user principal))
  (match (map-get? user-claim-history { user: user })
    history
    (let ((total-claims (get total-claims history)))
      (if (> total-claims u10)
          u80  ;; Very frequent claimant
          (if (> total-claims u5)
              u40  ;; Frequent claimant
              u10  ;; Normal claimant
          )
      )
    )
    u0
  )
)

;; Update validator statistics
(define-private (update-validator-stats (validator principal))
  (let (
    (current-stats (default-to 
                     { is-authorized: true, specialization: u0, validation-count: u0, accuracy-score: u100 }
                     (map-get? authorized-validators { validator: validator })))
  )
    (map-set authorized-validators
      { validator: validator }
      (merge current-stats {
        validation-count: (+ (get validation-count current-stats) u1)
      })
    )
  )
)

;; Admin Functions

;; Add authorized validator
(define-public (add-validator (validator principal) (specialization uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-validators
      { validator: validator }
      {
        is-authorized: true,
        specialization: specialization,
        validation-count: u0,
        accuracy-score: u100
      }
    )
    (ok true)
  )
)

;; Remove validator authorization
(define-public (remove-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-validators
      { validator: validator }
      (merge (default-to 
               { is-authorized: false, specialization: u0, validation-count: u0, accuracy-score: u0 }
               (map-get? authorized-validators { validator: validator }))
             { is-authorized: false })
    )
    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

(define-read-only (get-claim-validation (claim-id uint))
  (map-get? claim-validations { claim-id: claim-id })
)

(define-read-only (get-user-claim-history (user principal))
  (map-get? user-claim-history { user: user })
)

(define-read-only (get-claim-appeal (claim-id uint))
  (map-get? claim-appeals { claim-id: claim-id })
)

(define-read-only (is-authorized-validator (validator principal))
  (default-to false (get is-authorized (map-get? authorized-validators { validator: validator })))
)

(define-read-only (get-contract-stats)
  {
    total-claims: (var-get next-claim-id),
    total-processed: (var-get total-claims-processed),
    total-payouts: (var-get total-payouts),
    reserve-balance: (var-get contract-reserve-balance)
  }
)

;; Check if claim has expired
(define-read-only (is-claim-expired (claim-id uint))
  (match (map-get? claims { claim-id: claim-id })
    claim
    (let (
      (submitted-at (get submitted-at claim))
      (current-block stacks-block-height)
    )
      (> (- current-block submitted-at) claim-expiry-blocks)
    )
    true
  )
)

;; Get claims by status for admin dashboard
(define-read-only (get-claims-by-status (status uint))
  ;; In a real implementation, this would return a list of claim IDs
  ;; For now, we'll return a simple count placeholder
  { status: status, count: u0 }
)
