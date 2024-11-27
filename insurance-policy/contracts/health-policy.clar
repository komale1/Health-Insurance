;; Health Insurance Marketplace Smart Contract
;; Implements a decentralized marketplace for health insurance policies

;; Error Constants
(define-constant ERR_NOT_AUTHORIZED (err u1000))
(define-constant ERR_OWNER_ONLY (err u1001))
(define-constant ERR_ALREADY_REGISTERED (err u1002))
(define-constant ERR_NOT_REGISTERED (err u1003))
(define-constant ERR_INSUFFICIENT_FUNDS (err u1004))
(define-constant ERR_INVALID_POLICY (err u1005))
(define-constant ERR_POLICY_EXPIRED (err u1006))
(define-constant ERR_NOT_INSURED (err u1007))
(define-constant ERR_INVALID_AMOUNT (err u1008))
(define-constant ERR_INACTIVE_POLICY (err u1009))
(define-constant ERR_INVALID_CLAIM (err u1010))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u1011))
(define-constant ERR_INVALID_DURATION (err u1012))
(define-constant ERR_POLICY_LIMIT_REACHED (err u1013))
(define-constant ERR_INVALID_PREMIUM (err u1014))

;; Contract Owner
(define-constant CONTRACT_OWNER tx-sender)

;; Data Variables
(define-data-var total-insurance-pool-balance uint u0)
(define-data-var total-active-policies uint u0)
(define-data-var total-processed-claims uint u0)
(define-data-var is-contract-paused bool false)

;; Constants
(define-constant ANNUAL_BLOCK_COUNT u52560)
(define-constant MINIMUM_PREMIUM_THRESHOLD u1000)
(define-constant MAXIMUM_COVERAGE_LIMIT u1000000000)
(define-constant MAXIMUM_POLICIES_PER_INSURER u1000)

;; Principal Maps
(define-map registered-insurers principal
    {
        is-licensed: bool,
        active-policy-count: uint,
        insurer-rating: uint,
        is-active: bool,
        insurer-registration-time: uint,
        last-update-timestamp: uint
    }
)

(define-map registered-policyholders principal
    {
        is-policy-active: bool,
        policy-identifier: uint,
        total-coverage-amount: uint,
        monthly-premium-amount: uint,
        policy-start-block: uint,
        policy-end-block: uint,
        total-claims-submitted: uint,
        last-claim-submission-block: uint
    }
)

(define-map insurance-policies uint
    {
        policy-provider: principal,
        insurance-type: (string-ascii 64),
        monthly-premium-rate: uint,
        maximum-coverage-amount: uint,
        is-policy-active: bool,
        total-enrolled-members: uint,
        policy-creation-timestamp: uint,
        minimum-coverage-duration: uint,
        maximum-coverage-duration: uint
    }
)

(define-map insurance-claims uint
    {
        claim-submitter: principal,
        claim-amount: uint,
        claim-status: (string-ascii 20),
        claim-processing-block: uint,
        claim-description: (string-ascii 256),
        claim-processor: (optional principal),
        claim-processing-duration: uint
    }
)

;; Private Functions
(define-private (verify-contract-owner)
    (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (verify-premium-amount (proposed-premium uint))
    (>= proposed-premium MINIMUM_PREMIUM_THRESHOLD)
)

(define-private (verify-coverage-amount (proposed-coverage uint))
    (and 
        (> proposed-coverage u0)
        (<= proposed-coverage MAXIMUM_COVERAGE_LIMIT)
    )
)

;; Read-Only Functions
(define-read-only (get-insurer-information (insurer-address principal))
    (map-get? registered-insurers insurer-address)
)

(define-read-only (get-policyholder-information (policyholder-address principal))
    (map-get? registered-policyholders policyholder-address)
)

(define-read-only (get-policy-information (policy-identifier uint))
    (map-get? insurance-policies policy-identifier)
)

(define-read-only (get-claim-information (claim-identifier uint))
    (map-get? insurance-claims claim-identifier)
)

(define-read-only (get-total-pool-balance)
    (var-get total-insurance-pool-balance)
)

(define-read-only (check-contract-pause-status)
    (var-get is-contract-paused)
)

;; Public Functions

;; Register new insurer
(define-public (register-new-insurer)
    (let (
        (existing-insurer-data (map-get? registered-insurers tx-sender))
        (current-block-height block-height)
    )
    (asserts! (not (var-get is-contract-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (is-none existing-insurer-data) ERR_ALREADY_REGISTERED)
    (map-set registered-insurers tx-sender
        {
            is-licensed: true,
            active-policy-count: u0,
            insurer-rating: u100,
            is-active: true,
            insurer-registration-time: current-block-height,
            last-update-timestamp: current-block-height
        }
    )
    (ok true))
)

;; Create new insurance policy
(define-public (create-insurance-policy 
    (insurance-type (string-ascii 64)) 
    (monthly-premium uint) 
    (coverage-amount uint)
    (min-duration uint)
    (max-duration uint)
)
    (let (
        (insurer-data (unwrap! (map-get? registered-insurers tx-sender) ERR_NOT_REGISTERED))
        (new-policy-id (var-get total-active-policies))
        (current-block-height block-height)
    )
    (asserts! (not (var-get is-contract-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (get is-licensed insurer-data) ERR_NOT_AUTHORIZED)
    (asserts! (get is-active insurer-data) ERR_NOT_AUTHORIZED)
    (asserts! (< (get active-policy-count insurer-data) MAXIMUM_POLICIES_PER_INSURER) ERR_POLICY_LIMIT_REACHED)
    (asserts! (verify-premium-amount monthly-premium) ERR_INVALID_PREMIUM)
    (asserts! (verify-coverage-amount coverage-amount) ERR_INVALID_AMOUNT)
    (asserts! (>= max-duration min-duration) ERR_INVALID_DURATION)
    
    (map-set insurance-policies new-policy-id
        {
            policy-provider: tx-sender,
            insurance-type: insurance-type,
            monthly-premium-rate: monthly-premium,
            maximum-coverage-amount: coverage-amount,
            is-policy-active: true,
            total-enrolled-members: u0,
            policy-creation-timestamp: current-block-height,
            minimum-coverage-duration: min-duration,
            maximum-coverage-duration: max-duration
        }
    )
    (var-set total-active-policies (+ new-policy-id u1))
    (ok new-policy-id))
)

;; Purchase insurance policy
(define-public (purchase-insurance-policy (policy-identifier uint) (coverage-duration uint))
    (let (
        (selected-policy (unwrap! (map-get? insurance-policies policy-identifier) ERR_INVALID_POLICY))
        (current-block-height block-height)
        (monthly-premium-amount (get monthly-premium-rate selected-policy))
    )
    (asserts! (not (var-get is-contract-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (get is-policy-active selected-policy) ERR_INACTIVE_POLICY)
    (asserts! (is-none (map-get? registered-policyholders tx-sender)) ERR_ALREADY_REGISTERED)
    (asserts! (and 
        (>= coverage-duration (get minimum-coverage-duration selected-policy))
        (<= coverage-duration (get maximum-coverage-duration selected-policy))
    ) ERR_INVALID_DURATION)
    
    (try! (stx-transfer? monthly-premium-amount tx-sender (get policy-provider selected-policy)))
    
    ;; Update insurance pool
    (var-set total-insurance-pool-balance (+ (var-get total-insurance-pool-balance) monthly-premium-amount))
    
    ;; Register policyholder
    (map-set registered-policyholders tx-sender
        {
            is-policy-active: true,
            policy-identifier: policy-identifier,
            total-coverage-amount: (get maximum-coverage-amount selected-policy),
            monthly-premium-amount: monthly-premium-amount,
            policy-start-block: current-block-height,
            policy-end-block: (+ current-block-height (* coverage-duration ANNUAL_BLOCK_COUNT)),
            total-claims-submitted: u0,
            last-claim-submission-block: u0
        }
    )
    
    ;; Update enrollment count
    (map-set insurance-policies policy-identifier
        (merge selected-policy { total-enrolled-members: (+ (get total-enrolled-members selected-policy) u1) })
    )
    (ok true))
)

;; Submit insurance claim
(define-public (submit-insurance-claim (claim-amount uint) (claim-description (string-ascii 256)))
    (let (
        (policyholder-data (unwrap! (map-get? registered-policyholders tx-sender) ERR_NOT_INSURED))
        (policy-data (unwrap! (map-get? insurance-policies (get policy-identifier policyholder-data)) ERR_INVALID_POLICY))
        (new-claim-id (var-get total-processed-claims))
        (current-block-height block-height)
    )
    (asserts! (not (var-get is-contract-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (get is-policy-active policyholder-data) ERR_NOT_INSURED)
    (asserts! (<= claim-amount (get total-coverage-amount policyholder-data)) ERR_INVALID_AMOUNT)
    (asserts! (<= current-block-height (get policy-end-block policyholder-data)) ERR_POLICY_EXPIRED)
    
    ;; Create new claim
    (map-set insurance-claims new-claim-id
        {
            claim-submitter: tx-sender,
            claim-amount: claim-amount,
            claim-status: "PENDING",
            claim-processing-block: u0,
            claim-description: claim-description,
            claim-processor: none,
            claim-processing-duration: u0
        }
    )
    
    ;; Update claims counter
    (var-set total-processed-claims (+ new-claim-id u1))
    (ok new-claim-id))
)

;; Process insurance claim
(define-public (process-insurance-claim (claim-identifier uint) (approve-claim bool))
    (let (
        (claim-data (unwrap! (map-get? insurance-claims claim-identifier) ERR_INVALID_CLAIM))
        (policyholder-data (unwrap! (map-get? registered-policyholders (get claim-submitter claim-data)) ERR_NOT_INSURED))
        (policy-data (unwrap! (map-get? insurance-policies (get policy-identifier policyholder-data)) ERR_INVALID_POLICY))
        (current-block-height block-height)
    )
    (asserts! (not (var-get is-contract-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq tx-sender (get policy-provider policy-data)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get claim-status claim-data) "PENDING") ERR_CLAIM_ALREADY_PROCESSED)
    
    (if approve-claim
        (begin
            ;; Transfer claim amount
            (try! (stx-transfer? (get claim-amount claim-data) (get policy-provider policy-data) (get claim-submitter claim-data)))
            ;; Update claim status
            (map-set insurance-claims claim-identifier
                (merge claim-data { 
                    claim-status: "APPROVED",
                    claim-processing-block: current-block-height,
                    claim-processor: (some tx-sender),
                    claim-processing-duration: (- current-block-height (get claim-processing-block claim-data))
                })
            )
            ;; Update pool balance
            (var-set total-insurance-pool-balance (- (var-get total-insurance-pool-balance) (get claim-amount claim-data)))
        )
        ;; Reject claim
        (map-set insurance-claims claim-identifier
            (merge claim-data { 
                claim-status: "REJECTED",
                claim-processing-block: current-block-height,
                claim-processor: (some tx-sender),
                claim-processing-duration: (- current-block-height (get claim-processing-block claim-data))
            })
        )
    )
    (ok true))
)

;; Cancel insurance policy
(define-public (cancel-insurance-policy)
    (let (
        (policyholder-data (unwrap! (map-get? registered-policyholders tx-sender) ERR_NOT_INSURED))
        (policy-data (unwrap! (map-get? insurance-policies (get policy-identifier policyholder-data)) ERR_INVALID_POLICY))
        (remaining-block-count (- (get policy-end-block policyholder-data) block-height))
        (refund-amount (/ (* remaining-block-count (get monthly-premium-amount policyholder-data)) ANNUAL_BLOCK_COUNT))
    )
    (asserts! (not (var-get is-contract-paused)) ERR_NOT_AUTHORIZED)
    (asserts! (get is-policy-active policyholder-data) ERR_NOT_INSURED)
    
    ;; Process refund
    (try! (stx-transfer? refund-amount (get policy-provider policy-data) tx-sender))
    
    ;; Update pool balance
    (var-set total-insurance-pool-balance (- (var-get total-insurance-pool-balance) refund-amount))
    
    ;; Remove policyholder
    (map-delete registered-policyholders tx-sender)
    
    ;; Update enrollment count
    (map-set insurance-policies (get policy-identifier policyholder-data)
        (merge policy-data { total-enrolled-members: (- (get total-enrolled-members policy-data) u1) })
    )
    (ok true))
)

;; Contract pause/unpause
(define-public (set-contract-pause-status (pause-status bool))
    (begin
        (asserts! (verify-contract-owner) ERR_OWNER_ONLY)
        (var-set is-contract-paused pause-status)
        (ok true))
)

;; Emergency shutdown
(define-public (initiate-emergency-shutdown)
    (begin
        (asserts! (verify-contract-owner) ERR_OWNER_ONLY)
        (var-set is-contract-paused true)
        (ok true))
)