;; Weather-Based Agricultural Protection System
;; Automated compensation based on predefined climate triggers without requiring claims

;; Protection policies
(define-map protection-agreements
  { agreement-id: uint }
  {
    beneficiary: principal,
    location-id: (string-ascii 64),          ;; Geographic identifier
    crop-type: (string-ascii 32),            ;; Type of crop protected
    compensation-limit: uint,                ;; Maximum compensation amount
    premium-amount: uint,                    ;; Premium paid
    protection-begins: uint,                 ;; Block height when protection begins
    protection-expires: uint,                ;; Block height when protection ends
    status-active: bool,                     ;; Whether policy is currently active
    drought-threshold: int,                  ;; Rainfall threshold in mm below which compensation triggers
    excessive-rain-threshold: int,           ;; Rainfall threshold in mm above which compensation triggers
    freeze-threshold: int,                   ;; Temperature threshold in Celsius below which compensation triggers
    payout-executed: bool,                   ;; Whether a compensation has been executed
    weather-oracle: principal                ;; Weather data oracle
  }
)

;; Weather observation records
(define-map weather-observations
  { location-id: (string-ascii 64), timestamp: uint }
  {
    rainfall-mm: int,            ;; Rainfall in millimeters
    temperature-celsius: int,    ;; Temperature in Celsius
    humidity-level: uint,        ;; Humidity percentage
    data-provider: principal,    ;; Oracle that recorded data
    validation-status: bool      ;; Whether data is verified by multiple oracles
  }
)

;; Authorized weather data providers
(define-map certified-oracles
  { oracle-address: principal }
  {
    oracle-name: (string-utf8 128),
    certification-date: uint,
    certified-by: principal,
    active-status: bool
  }
)

;; Risk pools for each crop type
(define-map protection-pools
  { crop-type: (string-ascii 32) }
  {
    total-premiums: uint,        ;; Total premiums collected for this crop
    total-payouts: uint,         ;; Total compensations made
    active-policies: uint,       ;; Number of active policies
    reserve-ratio: uint,         ;; Target reserve ratio (out of 10000)
    pool-treasury: uint          ;; Current STX balance in the pool
  }
)

;; Next available policy ID
(define-data-var next-agreement-id uint u0)

;; Protocol fees
(define-data-var protocol-fee-percentage uint u500)  ;; 5% of premiums
(define-data-var treasury-address principal tx-sender)

;; Register an oracle provider
(define-public (register-weather-oracle (oracle-name (string-utf8 128)))
  (begin
    ;; In a real implementation, this would require governance approval
    ;; Simplified for this example
    
    (map-set certified-oracles
      { oracle-address: tx-sender }
      {
        oracle-name: oracle-name,
        certification-date: block-height,
        certified-by: tx-sender,
        active-status: true
      }
    )
    
    (ok true)
  )
)

;; Check if sender is an authorized oracle
(define-private (is-certified-oracle (oracle-address principal))
  (default-to 
    false 
    (get active-status (map-get? certified-oracles { oracle-address: oracle-address }))
  )
)

;; Create a new protection policy
(define-public (create-protection
                (location-id (string-ascii 64))
                (crop-type (string-ascii 32))
                (compensation-limit uint)
                (premium-amount uint)
                (coverage-duration uint)
                (drought-threshold int)
                (excessive-rain-threshold int)
                (freeze-threshold int)
                (weather-oracle principal))
  (let
    ((agreement-id (var-get next-agreement-id))
     (start-block block-height)
     (end-block (+ block-height coverage-duration))
     (protocol-fee (/ (* premium-amount (var-get protocol-fee-percentage)) u10000))
     (pool-deposit (- premium-amount protocol-fee)))
    
    ;; Validate parameters
    (asserts! (> compensation-limit u0) (err u"Compensation amount must be positive"))
    (asserts! (> premium-amount u0) (err u"Premium amount must be positive"))
    (asserts! (>= coverage-duration u1000) (err u"Coverage duration too short"))
    (asserts! (> drought-threshold (to-int u0)) (err u"Invalid drought threshold"))
    (asserts! (> excessive-rain-threshold drought-threshold) (err u"Invalid excess rain threshold"))
    (asserts! (< freeze-threshold (to-int u30)) (err u"Invalid frost threshold"))
    (asserts! (is-certified-oracle weather-oracle) (err u"Oracle provider not authorized"))
    
    ;; Transfer premium payment
    (asserts! (is-ok (stx-transfer? premium-amount tx-sender (as-contract tx-sender))) 
             (err u"Failed to transfer premium payment"))
    
    ;; Transfer protocol fee
    (asserts! (is-ok (as-contract (stx-transfer? protocol-fee tx-sender (var-get treasury-address))))
             (err u"Failed to transfer protocol fee"))
    
    ;; Create the policy
    (map-set protection-agreements
      { agreement-id: agreement-id }
      {
        beneficiary: tx-sender,
        location-id: location-id,
        crop-type: crop-type,
        compensation-limit: compensation-limit,
        premium-amount: premium-amount,
        protection-begins: start-block,
        protection-expires: end-block,
        status-active: true,
        drought-threshold: drought-threshold,
        excessive-rain-threshold: excessive-rain-threshold,
        freeze-threshold: freeze-threshold,
        payout-executed: false,
        weather-oracle: weather-oracle
      }
    )
    
    ;; Set next policy ID now to avoid any race conditions
    (var-set next-agreement-id (+ agreement-id u1))
    
    ;; Update risk pool
    (match (map-get? protection-pools { crop-type: crop-type })
      existing-pool (map-set protection-pools
                      { crop-type: crop-type }
                      {
                        total-premiums: (+ (get total-premiums existing-pool) pool-deposit),
                        total-payouts: (get total-payouts existing-pool),
                        active-policies: (+ (get active-policies existing-pool) u1),
                        reserve-ratio: (get reserve-ratio existing-pool),
                        pool-treasury: (+ (get pool-treasury existing-pool) pool-deposit)
                      }
                    )
      ;; Create new pool if it doesn't exist
      (map-set protection-pools
        { crop-type: crop-type }
        {
          total-premiums: pool-deposit,
          total-payouts: u0,
          active-policies: u1,
          reserve-ratio: u7000,  ;; Default 70% reserve ratio
          pool-treasury: pool-deposit
        }
      )
    )
    
    ;; Policy ID counter increment was moved above to avoid race conditions
    
    (ok agreement-id)
  )
)

;; Submit weather data (oracle only)
(define-public (record-weather-observation
                (location-id (string-ascii 64))
                (rainfall-mm int)
                (temperature-celsius int)
                (humidity-level uint))
  (begin
    ;; Validate oracle authorization
    (asserts! (is-certified-oracle tx-sender) (err u"Not authorized as oracle"))
    
    ;; Record weather data
    (map-set weather-observations
      { location-id: location-id, timestamp: block-height }
      {
        rainfall-mm: rainfall-mm,
        temperature-celsius: temperature-celsius,
        humidity-level: humidity-level,
        data-provider: tx-sender,
        validation-status: false  ;; Would need verification from multiple oracles in production
      }
    )
    
    ;; Process any policies that might be triggered by this data
    (try! (process-weather-triggers location-id))
    
    (ok true)
  )
)

;; Process weather triggers for policies
(define-private (process-weather-triggers (location-id (string-ascii 64)))
  (begin
    ;; In a real implementation, this would iterate through all policies for the location
    ;; and check trigger conditions. Simplified for this example.
    
    ;; Return early if no policies match, to avoid any future issues
    
    ;; For demonstration, we'll process a dummy policy ID 0
    (let ((agreement-opt (map-get? protection-agreements { agreement-id: u0 })))
      (if (is-some agreement-opt)
        (let ((protection (unwrap-panic agreement-opt)))
          (if (and (is-eq (get location-id protection) location-id)
                 (get status-active protection)
                 (not (get payout-executed protection))
                 (<= (get protection-begins protection) block-height)
                 (>= (get protection-expires protection) block-height))
            ;; Policy matches criteria, check triggers
            (let ((trigger-result (check-protection-triggers u0 protection)))
              (if (is-ok trigger-result)
                (ok true)
                trigger-result))
            ;; Policy doesn't match criteria
            (ok true)))
        ;; No policy found
        (ok true)))
  )
)

;; Check if policy triggers are met
(define-private (check-protection-triggers (agreement-id uint) (protection (tuple 
                                         (beneficiary principal)
                                         (location-id (string-ascii 64))
                                         (crop-type (string-ascii 32))
                                         (compensation-limit uint)
                                         (premium-amount uint)
                                         (protection-begins uint)
                                         (protection-expires uint)
                                         (status-active bool)
                                         (drought-threshold int)
                                         (excessive-rain-threshold int)
                                         (freeze-threshold int)
                                         (payout-executed bool)
                                         (weather-oracle principal))))
  (let
    ((weather-data (unwrap! (map-get? weather-observations 
                       { location-id: (get location-id protection), timestamp: block-height })
                      (err u"Weather data not found"))))
    
    ;; Check if any trigger conditions are met
    (if (or (< (get rainfall-mm weather-data) (get drought-threshold protection))
            (> (get rainfall-mm weather-data) (get excessive-rain-threshold protection))
            (< (get temperature-celsius weather-data) (get freeze-threshold protection)))
        ;; Trigger conditions met, execute payout
        (execute-protection-payout agreement-id)
        (ok false)
    )
  )
)

;; Execute policy payout
(define-private (execute-protection-payout (agreement-id uint))
  (let
    ((agreement-opt (map-get? protection-agreements { agreement-id: agreement-id })))
    
    ;; Check if policy exists
    (asserts! (is-some agreement-opt) (err u"Policy not found"))
    (let ((protection (unwrap-panic agreement-opt)))
      
      ;; Validate policy is active and payout not already executed
      (asserts! (get status-active protection) (err u"Policy not active"))
      (asserts! (not (get payout-executed protection)) (err u"Payout already executed"))
      
      ;; Update policy status
      (map-set protection-agreements
        { agreement-id: agreement-id }
        (merge protection { payout-executed: true, status-active: false })
      )
      
      ;; Update risk pool
      (let ((protection-pool (map-get? protection-pools { crop-type: (get crop-type protection) })))
        (asserts! (is-some protection-pool) (err u"Risk pool not found"))
        
        (let ((pool (unwrap-panic protection-pool)))
          (map-set protection-pools
            { crop-type: (get crop-type protection) }
            {
              total-premiums: (get total-premiums pool),
              total-payouts: (+ (get total-payouts pool) (get compensation-limit protection)),
              active-policies: (- (get active-policies pool) u1),
              reserve-ratio: (get reserve-ratio pool),
              pool-treasury: (- (get pool-treasury pool) (get compensation-limit protection))
            }
          )
        )
      )
      
      ;; Transfer payout to policyholder
      (asserts! (is-ok (as-contract (stx-transfer? (get compensation-limit protection) tx-sender (get beneficiary protection))))
                (err u"Failed to transfer payout"))
      
      (ok true)
    )
  )
)

;; Allow a user to cancel policy before end date (partial refund)
(define-public (terminate-protection (agreement-id uint))
  (let
    ((agreement-opt (map-get? protection-agreements { agreement-id: agreement-id })))
    
    ;; Validate policy exists
    (asserts! (is-some agreement-opt) (err u"Policy not found"))
    (let ((protection (unwrap-panic agreement-opt)))
      
      ;; Validate
      (asserts! (is-eq tx-sender (get beneficiary protection)) (err u"Not the policyholder"))
      (asserts! (get status-active protection) (err u"Policy not active"))
      (asserts! (not (get payout-executed protection)) (err u"Payout already executed"))
      
      ;; Calculate refund based on time remaining
      (let
        ((total-period (- (get protection-expires protection) (get protection-begins protection)))
         (elapsed-period (- block-height (get protection-begins protection)))
         (remaining-period (- total-period elapsed-period))
         (refund-rate (/ (* remaining-period u10000) total-period))
         (refund-value (/ (* (get premium-amount protection) refund-rate) u10000)))
        
        ;; Update policy status
        (map-set protection-agreements
          { agreement-id: agreement-id }
          (merge protection { status-active: false })
        )
        
        ;; Update risk pool
        (let ((protection-pool (map-get? protection-pools { crop-type: (get crop-type protection) })))
          (asserts! (is-some protection-pool) (err u"Risk pool not found"))
          
          (let ((pool (unwrap-panic protection-pool)))
            (map-set protection-pools
              { crop-type: (get crop-type protection) }
              {
                total-premiums: (get total-premiums pool),
                total-payouts: (get total-payouts pool),
                active-policies: (- (get active-policies pool) u1),
                reserve-ratio: (get reserve-ratio pool),
                pool-treasury: (- (get pool-treasury pool) refund-value)
              }
            )
          )
        )
        
        ;; Transfer refund to policyholder
        (asserts! (is-ok (as-contract (stx-transfer? refund-value tx-sender (get beneficiary protection))))
                  (err u"Failed to transfer refund"))
        
        (ok refund-value)
      )
    )
  )
)

;; Verify weather data (multiple oracles required)
(define-public (validate-weather-observation
                (location-id (string-ascii 64))
                (timestamp uint)
                (rainfall-mm int)
                (temperature-celsius int)
                (humidity-level uint))
  (let
    ((weather-record (unwrap! (map-get? weather-observations 
                              { location-id: location-id, timestamp: timestamp })
                             (err u"Weather data not found"))))
    
    ;; Validate oracle authorization
    (asserts! (is-certified-oracle tx-sender) (err u"Not authorized as oracle"))
    (asserts! (not (is-eq tx-sender (get data-provider weather-record))) 
              (err u"Cannot verify own data"))
    
    ;; Check if data matches within acceptable margin of error
    (asserts! (< (abs (- rainfall-mm (get rainfall-mm weather-record))) (to-int u5)) 
              (err u"Rainfall data differs too much"))
    (asserts! (< (abs (- temperature-celsius (get temperature-celsius weather-record))) (to-int u2)) 
              (err u"Temperature data differs too much"))
    (asserts! (< (abs-uint humidity-level (get humidity-level weather-record)) u5) 
              (err u"Humidity data differs too much"))
    
    ;; Mark data as verified
    (map-set weather-observations
      { location-id: location-id, timestamp: timestamp }
      (merge weather-record { validation-status: true })
    )
    
    (ok true)
  )
)

;; Manually trigger policy evaluation (for testing or backup)
(define-public (assess-protection (agreement-id uint))
  (let
    ((protection (unwrap! (map-get? protection-agreements { agreement-id: agreement-id }) 
                     (err u"Policy not found")))
     (current-weather (get-current-weather (get location-id protection))))
    
    ;; Validate
    (asserts! (or (is-eq tx-sender (get beneficiary protection))
                 (is-eq tx-sender (get weather-oracle protection)))
              (err u"Not authorized"))
    (asserts! (get status-active protection) (err u"Policy not active"))
    (asserts! (not (get payout-executed protection)) (err u"Payout already executed"))
    (asserts! (is-some current-weather) (err u"No weather data available"))
    
    ;; Check if any trigger conditions are met
    (let ((weather-data (unwrap-panic current-weather)))
      (if (or (< (get rainfall-mm weather-data) (get drought-threshold protection))
              (> (get rainfall-mm weather-data) (get excessive-rain-threshold protection))
              (< (get temperature-celsius weather-data) (get freeze-threshold protection)))
          ;; Trigger conditions met, execute payout
          (execute-protection-payout agreement-id)
          (ok false)
      )
    )
  )
)

;; Get latest weather data for a location
(define-private (get-current-weather (location-id (string-ascii 64)))
  ;; In a real implementation, this would search for the most recent data
  ;; Simplified for this example
  (map-get? weather-observations { location-id: location-id, timestamp: block-height })
)

;; Utility function for absolute value (int)
(define-private (abs (x int))
  (if (< x (to-int u0)) (to-int (- u0 (to-uint x))) x)
)

;; Utility function for absolute value (uint)
(define-private (abs-uint (x uint) (y uint))
  (if (> x y) (- x y) (- y x))
)

;; Read-only functions

;; Get policy details
(define-read-only (get-protection-details (agreement-id uint))
  (ok (unwrap! (map-get? protection-agreements { agreement-id: agreement-id }) (err u"Policy not found")))
)

;; Get weather data
(define-read-only (get-weather-observation (location-id (string-ascii 64)) (timestamp uint))
  (ok (unwrap! (map-get? weather-observations { location-id: location-id, timestamp: timestamp })
              (err u"Weather data not found")))
)

;; Get risk pool information
(define-read-only (get-protection-pool (crop-type (string-ascii 32)))
  (ok (unwrap! (map-get? protection-pools { crop-type: crop-type }) (err u"Risk pool not found")))
)

;; Check if oracle is authorized
(define-read-only (check-oracle-certification (oracle-address principal))
  (ok (is-certified-oracle oracle-address))
)