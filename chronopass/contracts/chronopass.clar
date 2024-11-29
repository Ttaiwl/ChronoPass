;; ChronoPass: Dynamic NFT Subscription System

;; Constants and Settings
(define-constant contract-owner tx-sender)
(define-constant blocks-per-day u144)
(define-constant min-subscription-days u1)
(define-constant max-subscription-days u365)

;; Error Codes
(define-constant err-unauthorized (err u100))
(define-constant err-expired (err u101))
(define-constant err-invalid-params (err u102))
(define-constant err-subscription-exists (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-invalid-duration (err u105))

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

;; Internal Functions
(define-private (validate-duration (days uint))
  (and 
    (>= days min-subscription-days)
    (<= days max-subscription-days)
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
(define-public (set-tier (tier-id uint) (price uint) (duration uint) (max-renewals uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (validate-duration duration) err-invalid-duration)
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
    (asserts! (var-get service-active) err-unauthorized)
    (asserts! (>= (stx-get-balance tx-sender) (get price tier-data)) err-insufficient-funds)
    (try! (stx-transfer? (get price tier-data) tx-sender contract-owner))
    (try! (nft-mint? chronopass token-id tx-sender))
    (map-set subscriptions token-id {
      owner: tx-sender,
      start-time: block-height,
      end-time: end-time,
      tier: tier,
      auto-renewal: false,
      features: (list u1 u2 u3)
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
    (asserts! (and (var-get service-active) (is-eq tx-sender (get owner sub-data))) err-unauthorized)
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
    (asserts! (is-eq tx-sender (get owner sub-data)) err-unauthorized)
    (ok (map-set subscriptions token-id
      (merge sub-data {
        auto-renewal: (not (get auto-renewal sub-data))
      })
    ))
  ))
)

;; Read-Only Functions
(define-read-only (get-subscription (token-id uint))
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
  )
  (ok {
    is-active: (is-active sub-data),
    details: sub-data
  }))
)

(define-read-only (has-feature (token-id uint) (feature-id uint))
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
  )
  (ok (and 
    (is-active sub-data)
    (is-some (index-of (get features sub-data) feature-id))
  )))
)

;; NFT Transfer Implementation
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (let (
    (sub-data (unwrap! (map-get? subscriptions token-id) err-invalid-params))
  )
  (begin
    (asserts! (is-eq (get owner sub-data) sender) err-unauthorized)
    (try! (nft-transfer? chronopass token-id sender recipient))
    (ok (map-set subscriptions token-id
      (merge sub-data {
        owner: recipient,
        auto-renewal: false
      })
    ))
  ))
)

(define-read-only (get-owner (token-id uint))
  (ok (get owner (unwrap! (map-get? subscriptions token-id) err-invalid-params)))
)

(define-read-only (get-token-uri (token-id uint))
  (ok none)
)