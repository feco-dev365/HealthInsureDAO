;; Dynamic Premium Calculator
;; A smart contract for calculating insurance premiums based on health metrics
;; Version: 1.0.0

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-data (err u103))

;; Data maps
(define-map user-profiles
  { user: principal }
  {
    base-premium: uint,
    risk-factor: uint,
    last-updated: uint
  }
)

(define-map health-metrics
  { user: principal }
  {
    heart-rate-avg: uint,
    steps-daily-avg: uint,
    sleep-hours-avg: uint,
    blood-pressure-systolic: uint,
    blood-pressure-diastolic: uint,
    last-updated: uint
  }
)

(define-map authorized-data-providers
  { provider: principal }
  { is-authorized: bool }
)

;; Public functions

;; Register a new user with initial profile
(define-public (register-user (base-premium uint) (risk-factor uint))
  (let ((user tx-sender))
    (if (is-some (map-get? user-profiles { user: user }))
      err-already-exists
      (begin
        (map-set user-profiles
          { user: user }
          {
            base-premium: base-premium,
            risk-factor: risk-factor,
            last-updated: stacks-block-height
          }
        )
        (ok true)
      )
    )
  )
)

;; Update health metrics - can only be called by authorized data providers
(define-public (update-health-metrics 
                (user principal)
                (heart-rate-avg uint)
                (steps-daily-avg uint)
                (sleep-hours-avg uint)
                (blood-pressure-systolic uint)
                (blood-pressure-diastolic uint))
  (let ((provider tx-sender))
    (asserts! (is-authorized-provider provider) err-owner-only)
    (map-set health-metrics
      { user: user }
      {
        heart-rate-avg: heart-rate-avg,
        steps-daily-avg: steps-daily-avg,
        sleep-hours-avg: sleep-hours-avg,
        blood-pressure-systolic: blood-pressure-systolic,
        blood-pressure-diastolic: blood-pressure-diastolic,
        last-updated: stacks-block-height
      }
    )
    (ok true)
  )
)

;; Calculate premium based on health metrics and base premium
(define-read-only (calculate-premium (user principal))
  (let (
    (profile (unwrap! (map-get? user-profiles { user: user }) err-not-found))
    (metrics (unwrap! (map-get? health-metrics { user: user }) err-not-found))
    (base-premium (get base-premium profile))
    (risk-factor (get risk-factor profile))
    
    ;; Health score calculations (lower is better)
    (heart-rate-score (heart-rate-risk (get heart-rate-avg metrics)))
    (steps-score (steps-risk (get steps-daily-avg metrics)))
    (sleep-score (sleep-risk (get sleep-hours-avg metrics)))
    (blood-pressure-score (blood-pressure-risk 
                           (get blood-pressure-systolic metrics)
                           (get blood-pressure-diastolic metrics)))
    
    ;; Combined health score
    (health-score (+ heart-rate-score steps-score sleep-score blood-pressure-score))
    
    ;; Final premium calculation
    (health-multiplier (/ (* health-score risk-factor) u100))
    (final-premium (+ base-premium health-multiplier))
  )
    (ok final-premium)
  )
)

;; Pay premium
(define-public (pay-premium)
  (let (
    (user tx-sender)
    (premium-result (calculate-premium user))
  )
    (if (is-ok premium-result)
      (let ((premium (unwrap! premium-result err-invalid-data)))
        ;; Premium payment logic would go here
        ;; This would typically involve a token transfer
        (ok premium)
      )
      premium-result
    )
  )
)

;; Admin functions

;; Add authorized data provider
(define-public (add-data-provider (provider principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-data-providers
      { provider: provider }
      { is-authorized: true }
    )
    (ok true)
  )
)

;; Remove authorized data provider
(define-public (remove-data-provider (provider principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set authorized-data-providers
      { provider: provider }
      { is-authorized: false }
    )
    (ok true)
  )
)

;; Helper functions

;; Check if a provider is authorized
(define-read-only (is-authorized-provider (provider principal))
  (default-to false (get is-authorized (map-get? authorized-data-providers { provider: provider })))
)

;; Risk calculation functions
(define-read-only (heart-rate-risk (heart-rate-avg uint))
  (if (< heart-rate-avg u60) 
      u15  ;; Too low
      (if (< heart-rate-avg u70)
          u5   ;; Optimal
          (if (< heart-rate-avg u80)
              u10  ;; Good
              (if (< heart-rate-avg u90)
                  u20  ;; Elevated
                  u30  ;; High
              )
          )
      )
  )
)

(define-read-only (steps-risk (steps-daily-avg uint))
  (if (< steps-daily-avg u3000)
      u30   ;; Very sedentary
      (if (< steps-daily-avg u6000)
          u20   ;; Sedentary
          (if (< steps-daily-avg u9000)
              u10   ;; Moderately active
              (if (< steps-daily-avg u12000)
                  u5   ;; Active
                  u0   ;; Very active
              )
          )
      )
  )
)

(define-read-only (sleep-risk (sleep-hours-avg uint))
  (if (< sleep-hours-avg u5)
      u30    ;; Very poor
      (if (< sleep-hours-avg u6)
          u20    ;; Poor
          (if (< sleep-hours-avg u7)
              u10    ;; Fair
              (if (< sleep-hours-avg u8)
                  u5     ;; Good
                  u0     ;; Optimal
              )
          )
      )
  )
)

(define-read-only (blood-pressure-risk (systolic uint) (diastolic uint))
  (if (and (< systolic u120) (< diastolic u80))
      u0    ;; Normal blood pressure
      (if (and (< systolic u130) (< diastolic u80))
          u10    ;; Elevated
          (if (or (< systolic u140) (< diastolic u90))
              u20    ;; Stage 1 hypertension
              u40    ;; Stage 2 hypertension or higher
          )
      )
  )
)