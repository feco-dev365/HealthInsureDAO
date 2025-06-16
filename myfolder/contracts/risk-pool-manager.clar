;; Risk Pool Management System for HealthInsureDAO
;; 
;; This contract manages risk pools by automatically categorizing users based on their
;; health profiles and risk scores. It enables fair premium distribution among users
;; with similar risk profiles and implements dynamic pool rebalancing as health
;; metrics change over time.
;;
;; Key Features:
;; - Automatic risk pool assignment based on composite health scores
;; - Pool-based premium adjustments and risk sharing mechanisms
;; - Dynamic rebalancing when users' health profiles change
;; - Pool statistics and analytics for transparency
;; - Incentive mechanisms for maintaining healthy pool averages

(define-constant contract-owner tx-sender)

;; Error constants
(define-constant err-owner-only (err u200))
(define-constant err-user-not-found (err u201))
(define-constant err-pool-not-found (err u202))
(define-constant err-invalid-pool-id (err u203))
(define-constant err-user-already-in-pool (err u204))
(define-constant err-insufficient-pool-size (err u205))
(define-constant err-invalid-health-score (err u206))
(define-constant err-pools-already-initialized (err u207))

;; Pool configuration constants
(define-constant max-pools u5)
(define-constant min-pool-size u10)
(define-constant rebalance-threshold u20) ;; Percentage change to trigger rebalancing

;; Risk pool tiers based on health scores (lower score = better health)
(define-constant excellent-health-max u25)    ;; Pool 1: 0-25
(define-constant good-health-max u50)         ;; Pool 2: 26-50  
(define-constant average-health-max u75)      ;; Pool 3: 51-75
(define-constant poor-health-max u100)        ;; Pool 4: 76-100
;; Pool 5: 101+ (high risk)

;; Data Maps

;; Risk pool definitions
(define-map risk-pools
  { pool-id: uint }
  {
    pool-name: (string-ascii 50),
    min-health-score: uint,
    max-health-score: uint,
    base-multiplier: uint,      ;; Premium multiplier (100 = 1.0x)
    member-count: uint,
    total-premiums: uint,
    average-health-score: uint,
    last-rebalanced: uint
  }
)

;; User pool assignments
(define-map user-pool-assignments
  { user: principal }
  {
    current-pool-id: uint,
    health-score: uint,
    assigned-at: uint,
    premium-adjustment: uint    ;; Pool-based adjustment percentage
  }
)

;; Pool membership tracking
(define-map pool-members
  { pool-id: uint, user: principal }
  {
    joined-at: uint,
    contribution-score: uint,   ;; User's contribution to pool health
    months-in-pool: uint
  }
)

;; Pool statistics for analytics
(define-map pool-statistics
  { pool-id: uint }
  {
    total-claims: uint,
    total-payouts: uint,
    average-age: uint,
    retention-rate: uint,
    improvement-rate: uint      ;; % of users improving health scores
  }
)

;; Data variables
(define-data-var total-pools uint u0)
(define-data-var last-global-rebalance uint u0)
(define-data-var pools-initialized bool false)

;; Initialization function (called once)
(define-public (initialize-pools)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get pools-initialized)) err-pools-already-initialized)
    
    ;; Create default risk pools
    (unwrap! (create-pool u1 "Excellent Health" u0 excellent-health-max u80) err-invalid-pool-id)
    (unwrap! (create-pool u2 "Good Health" (+ excellent-health-max u1) good-health-max u90) err-invalid-pool-id)
    (unwrap! (create-pool u3 "Average Health" (+ good-health-max u1) average-health-max u100) err-invalid-pool-id)
    (unwrap! (create-pool u4 "Poor Health" (+ average-health-max u1) poor-health-max u120) err-invalid-pool-id)
    (unwrap! (create-pool u5 "High Risk" (+ poor-health-max u1) u999 u150) err-invalid-pool-id)
    
    (var-set total-pools u5)
    (var-set last-global-rebalance stacks-block-height)
    (var-set pools-initialized true)
    (ok true)
  )
)

;; Create a new risk pool - now returns a response
(define-private (create-pool (pool-id uint) (name (string-ascii 50)) (min-score uint) (max-score uint) (multiplier uint))
  (begin
    (map-set risk-pools
      { pool-id: pool-id }
      {
        pool-name: name,
        min-health-score: min-score,
        max-health-score: max-score,
        base-multiplier: multiplier,
        member-count: u0,
        total-premiums: u0,
        average-health-score: u0,
        last-rebalanced: stacks-block-height
      }
    )
    (map-set pool-statistics
      { pool-id: pool-id }
      {
        total-claims: u0,
        total-payouts: u0,
        average-age: u0,
        retention-rate: u100,
        improvement-rate: u0
      }
    )
    (ok pool-id)
  )
)

;; Assign user to appropriate risk pool based on health score
(define-public (assign-user-to-pool (user principal) (health-score uint))
  (let (
    (target-pool-id (determine-pool-by-health-score health-score))
    (current-assignment (map-get? user-pool-assignments { user: user }))
  )
    (begin
      (asserts! (> health-score u0) err-invalid-health-score)
      (asserts! (<= target-pool-id (var-get total-pools)) err-invalid-pool-id)
      (asserts! (var-get pools-initialized) err-pool-not-found)
      
      ;; Remove from current pool if exists
      (match current-assignment
        assignment (unwrap! (remove-user-from-pool user (get current-pool-id assignment)) err-pool-not-found)
        true
      )
      
      ;; Add to new pool
      (unwrap! (add-user-to-pool user target-pool-id health-score) err-pool-not-found)
      (ok target-pool-id)
    )
  )
)

;; Add user to specific pool - now returns a response
(define-private (add-user-to-pool (user principal) (pool-id uint) (health-score uint))
  (let (
    (pool (unwrap! (map-get? risk-pools { pool-id: pool-id }) err-pool-not-found))
    (premium-adjustment (get base-multiplier pool))
    (current-member-count (get member-count pool))
    (current-avg (get average-health-score pool))
  )
    (begin
      ;; Update user assignment
      (map-set user-pool-assignments
        { user: user }
        {
          current-pool-id: pool-id,
          health-score: health-score,
          assigned-at: stacks-block-height,
          premium-adjustment: premium-adjustment
        }
      )
      
      ;; Add to pool membership
      (map-set pool-members
        { pool-id: pool-id, user: user }
        {
          joined-at: stacks-block-height,
          contribution-score: health-score,
          months-in-pool: u0
        }
      )
      
      ;; Update pool statistics
      (map-set risk-pools
        { pool-id: pool-id }
        (merge pool {
          member-count: (+ current-member-count u1),
          average-health-score: (calculate-new-pool-average current-avg current-member-count health-score)
        })
      )
      
      (ok true)
    )
  )
)

;; Remove user from pool - now returns a response
(define-private (remove-user-from-pool (user principal) (pool-id uint))
  (let (
    (pool (unwrap! (map-get? risk-pools { pool-id: pool-id }) err-pool-not-found))
    (membership (map-get? pool-members { pool-id: pool-id, user: user }))
    (current-count (get member-count pool))
  )
    (begin
      ;; Only proceed if user is actually in the pool
      (match membership
        member-data
        (begin
          ;; Remove pool membership
          (map-delete pool-members { pool-id: pool-id, user: user })
          
          ;; Update pool member count (ensure it doesn't go below 0)
          (map-set risk-pools
            { pool-id: pool-id }
            (merge pool { 
              member-count: (if (> current-count u0) (- current-count u1) u0)
            })
          )
          (ok true)
        )
        (ok true) ;; User wasn't in pool, that's fine
      )
    )
  )
)

;; Determine appropriate pool based on health score
(define-read-only (determine-pool-by-health-score (health-score uint))
  (if (<= health-score excellent-health-max)
      u1
      (if (<= health-score good-health-max)
          u2
          (if (<= health-score average-health-max)
              u3
              (if (<= health-score poor-health-max)
                  u4
                  u5
              )
          )
      )
  )
)

;; Calculate new pool average when adding a member
(define-read-only (calculate-new-pool-average (current-avg uint) (current-count uint) (new-score uint))
  (if (is-eq current-count u0)
      new-score
      (/ (+ (* current-avg current-count) new-score) (+ current-count u1))
  )
)

;; Rebalance user if health score changed significantly
(define-public (rebalance-user (user principal) (new-health-score uint))
  (let (
    (current-assignment (unwrap! (map-get? user-pool-assignments { user: user }) err-user-not-found))
    (current-score (get health-score current-assignment))
    (current-pool-id (get current-pool-id current-assignment))
    (target-pool-id (determine-pool-by-health-score new-health-score))
    (score-change (if (> new-health-score current-score)
                      (- new-health-score current-score)
                      (- current-score new-health-score)))
  )
    (begin
      (asserts! (> new-health-score u0) err-invalid-health-score)
      
      ;; Check if rebalancing is needed
      (if (or (not (is-eq current-pool-id target-pool-id))
              (> score-change rebalance-threshold))
          (assign-user-to-pool user new-health-score)
          (begin
            ;; Update health score in current pool
            (map-set user-pool-assignments
              { user: user }
              (merge current-assignment { health-score: new-health-score })
            )
            (ok current-pool-id)
          )
      )
    )
  )
)

;; Calculate pool-adjusted premium for user
(define-read-only (calculate-pool-adjusted-premium (user principal) (base-premium uint))
  (match (map-get? user-pool-assignments { user: user })
    assignment 
    (let (
      (adjustment (get premium-adjustment assignment))
      (adjusted-premium (/ (* base-premium adjustment) u100))
    )
      (ok adjusted-premium)
    )
    err-user-not-found
  )
)

;; Get pool incentive bonus (better pools get discounts)
(define-read-only (get-pool-incentive-bonus (pool-id uint))
  (match (map-get? risk-pools { pool-id: pool-id })
    pool
    (let ((avg-score (get average-health-score pool)))
      (if (<= avg-score excellent-health-max)
          u10  ;; 10% discount for excellent health pool
          (if (<= avg-score good-health-max)
              u5   ;; 5% discount for good health pool
              u0   ;; No discount for other pools
          )
      )
    )
    u0
  )
)

;; Admin function to manually create a pool
(define-public (admin-create-pool (pool-id uint) (name (string-ascii 50)) (min-score uint) (max-score uint) (multiplier uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-none (map-get? risk-pools { pool-id: pool-id })) err-user-already-in-pool)
    (unwrap! (create-pool pool-id name min-score max-score multiplier) err-invalid-pool-id)
    (var-set total-pools (+ (var-get total-pools) u1))
    (ok pool-id)
  )
)

;; Read-only functions

(define-read-only (get-user-pool-info (user principal))
  (map-get? user-pool-assignments { user: user })
)

(define-read-only (get-pool-info (pool-id uint))
  (map-get? risk-pools { pool-id: pool-id })
)

(define-read-only (get-pool-statistics (pool-id uint))
  (map-get? pool-statistics { pool-id: pool-id })
)

(define-read-only (get-user-pool-membership (pool-id uint) (user principal))
  (map-get? pool-members { pool-id: pool-id, user: user })
)

(define-read-only (is-pools-initialized)
  (var-get pools-initialized)
)

;; Get all pools summary
(define-read-only (get-pools-summary)
  (let (
    (pool1 (map-get? risk-pools { pool-id: u1 }))
    (pool2 (map-get? risk-pools { pool-id: u2 }))
    (pool3 (map-get? risk-pools { pool-id: u3 }))
    (pool4 (map-get? risk-pools { pool-id: u4 }))
    (pool5 (map-get? risk-pools { pool-id: u5 }))
  )
    {
      pool-1: pool1,
      pool-2: pool2,
      pool-3: pool3,
      pool-4: pool4,
      pool-5: pool5,
      total-pools: (var-get total-pools),
      last-rebalance: (var-get last-global-rebalance),
      initialized: (var-get pools-initialized)
    }
  )
)

;; Check if user needs rebalancing
(define-read-only (needs-rebalancing (user principal) (current-health-score uint))
  (match (map-get? user-pool-assignments { user: user })
    assignment
    (let (
      (stored-score (get health-score assignment))
      (current-pool (get current-pool-id assignment))
      (target-pool (determine-pool-by-health-score current-health-score))
    )
      (not (is-eq current-pool target-pool))
    )
    true
  )
)

;; Get user's current pool name for display
(define-read-only (get-user-pool-name (user principal))
  (match (map-get? user-pool-assignments { user: user })
    assignment
    (let ((pool-id (get current-pool-id assignment)))
      (match (map-get? risk-pools { pool-id: pool-id })
        pool (some (get pool-name pool))
        none
      )
    )
    none
  )
)