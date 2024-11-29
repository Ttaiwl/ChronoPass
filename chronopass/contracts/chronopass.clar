;; ChronoPass: Dynamic NFT Subscription System with Enhanced Safety

;; Constants and Settings
(define-constant contract-owner tx-sender)
(define-constant blocks-per-day u144)
(define-constant min-subscription-days u1)
(define-constant max-subscription-days u365)
(define-constant max-tier-price u1000000)  ;; Reasonable max price limit
(define-constant max-renewals-limit u10)   ;; Reasonable max renewals limit

;; Error Codes
(define-constant err-unauthorized (err u100))
(define-constant err-expired (err u101))
(define-constant err-invalid-params (err u102))
(define-constant err-subscription-exists (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-invalid-duration (err u105))
(define-constant err-transfer-not-allowed (err u106))
(define-constant err-transfer-expired (err u107))
(define-constant err-invalid-tier-config (err u108))

;; NFT Definition
(define-non-fungible-token chronopass uint)

;; Storage
(define-map subscriptions uint 
  {
    owner: principal,
    start-time: uint,
    end-time: uint,
    tier: uint,
    auto-renewal: bool,
    features: (list 10 uint)
  }
)

(define-map tiers uint 
  {
    price: uint,
    duration: uint,
    max-renewals: uint
  }
)

(define-data-var nft-counter uint u0)
(define-data-var service-active bool true)

;; Input Validation Functions
(define-private (validate-duration (days uint))
  (and 
    (>= days min-subscription-days)
    (<= days max-subscription-days)
  )
)

(define-private (validate-tier-config 
  (price uint) 
  (duration uint) 
  (max-renewals uint)
)
  (and
    (<= price max-tier-price)
    (validate-duration duration)
    (<= max-renewals max-renewals-limit)
  )
)

(define-private (is-active (sub-data {owner: principal, start-time: uint, end-time: uint, tier: uint, auto-renewal: bool, features: (list 10 uint)}))
  (and 
    (>= block-height (get start-time sub-data))
    (<= block-height (get end-time sub-data))
  )
)

(define-private (calculate-end-time (duration uint))
  (+ block-height (* duration blocks-per-day))
)

;; Administrative Functions
(define-public (set-tier 
  (tier-id uint) 
  (price uint) 
  (duration uint) 
  (max-renewals uint)
)
  (begin
    ;; Validate caller and tier configuration
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (validate-tier-config price duration max-renewals) err-invalid-tier-config)
    
    ;; Safe map-set with validated inputs
    (ok (map-set tiers tier-id {
      price: price,
      duration: duration,
      max-renewals: max-renewals
    }))
  )
)

(define-public (toggle-service)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (ok (var-set service-active (not (var-get service-active))))
  )
)

;; Core Subscription Functions
(define-public (mint-subscription (tier uint))
  (let (
    (tier-data (unwrap! (map-get? tiers tier) err-invalid-params))
    (token-id (+ (var-get nft-counter) u1))
    (end-time (calculate-end-time (get duration tier-data)))
  )
  (begin
    ;; Comprehensive input validation
    (asserts! (var-get service-active) err-unauthorized)
    (asserts! (is-some (map-get? tiers tier)) err-invalid-params)
    (asserts! (>= (stx-get-balance tx-sender) (get price tier-data)) err-insufficient-funds)
    
    ;; Safe token minting and subscription creation
    (try! (stx-transfer? (get price tier-data) tx-sender contract-owner))
    (try! (nft-mint? chronopass token-id tx-sender))
    (map-set subscriptions token-id {
      owner: tx-sender,
      start-time: block-height,
      end-time: end-time,
      tier: tier,
      auto-renewal: false,
      features: (list u1 u2 u3)  ;; Default features
    })
    (var-set nft-counter token-id)
    (ok token-id)
  ))
)

(define-public (renew-subscription (token-id uint))
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
    (tier-data (unwrap! (map-get? tiers (get tier sub-data)) err-invalid-params))
    (new-end-time (calculate-end-time (get duration tier-data)))
  )
  (begin
    ;; Enhanced validation for renewal
    (asserts! (var-get service-active) err-unauthorized)
    (asserts! (is-eq tx-sender (get owner sub-data)) err-unauthorized)
    (asserts! (is-active sub-data) err-expired)
    
    ;; Safe renewal process
    (try! (stx-transfer? (get price tier-data) tx-sender contract-owner))
    (ok (map-set subscriptions token-id
      (merge sub-data {
        end-time: new-end-time
      })
    ))
  ))
)

(define-public (toggle-auto-renewal (token-id uint))
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
  )
  (begin
    ;; Validate ownership
    (asserts! (is-eq tx-sender (get owner sub-data)) err-unauthorized)
    
    ;; Safe toggle of auto-renewal
    (ok (map-set subscriptions token-id
      (merge sub-data {
        auto-renewal: (not (get auto-renewal sub-data))
      })
    ))
  ))
)

;; Enhanced Transfer Function
(define-public (transfer-subscription 
  (token-id uint) 
  (sender principal) 
  (recipient principal)
  (transfer-features bool)
)
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
    (current-owner (get owner sub-data))
    (is-current-subscription-active (is-active sub-data))
  )
  (begin
    ;; Comprehensive transfer validation
    (asserts! (is-eq current-owner sender) err-unauthorized)
    (asserts! is-current-subscription-active err-transfer-expired)
    (asserts! (not (is-eq recipient tx-sender)) err-transfer-not-allowed)
    
    ;; Safe NFT and subscription transfer
    (try! (nft-transfer? chronopass token-id sender recipient))
    
    ;; Update subscription with robust transfer rules
    (map-set subscriptions token-id
      (merge sub-data {
        owner: recipient,
        auto-renewal: false,
        features: (if transfer-features 
                    (get features sub-data)
                    (list)
        )
      })
    )
    
    (ok true)
  ))
)

;; Read-Only Functions with Enhanced Validation
(define-read-only (get-subscription (token-id uint))
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
    (safe-active-check (is-active sub-data))
  )
  (ok {
    is-active: safe-active-check,
    details: sub-data
  }))
)

(define-read-only (has-feature (token-id uint) (feature-id uint))
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
    (safe-active-check (is-active sub-data))
  )
  (ok (and 
    safe-active-check
    (is-some (index-of (get features sub-data) feature-id))
  )))
)

;; Ownership and Transfer Verification
(define-read-only (verify-subscription-ownership 
  (token-id uint) 
  (expected-owner principal)
)
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
    (current-owner (get owner sub-data))
  )
  (ok (is-eq current-owner expected-owner))
))

;; Public Function to Verify Subscription State for Off-Chain Services
(define-read-only (verify-subscription-access 
  (token-id uint)
  (feature-id uint)
)
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
    (is-subscription-valid (is-active sub-data))
  )
  (ok {
    is-active: is-subscription-valid,
    owner: (get owner sub-data),
    has-feature: (is-some (index-of (get features sub-data) feature-id))
  }))
)

;; Legacy Transfer Function (for compatibility)
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (transfer-subscription token-id sender recipient false)
)

;; NFT Owner Retrieval
(define-read-only (get-owner (token-id uint))
  (ok (get owner (unwrap! (map-get? subscriptions token-id) err-invalid-params)))
)

;; Token URI (currently returns none, can be expanded later)
(define-read-only (get-token-uri (token-id uint))
  (ok none)
)