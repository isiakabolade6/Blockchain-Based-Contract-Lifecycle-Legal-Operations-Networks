;; Negotiation Tracking Contract
;; Tracks contract negotiations and amendments

;; Constants
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_INVALID_NEGOTIATION (err u301))
(define-constant ERR_NEGOTIATION_CLOSED (err u302))
(define-constant ERR_INVALID_PROPOSAL (err u303))

;; Data Variables
(define-data-var negotiation-counter uint u0)
(define-data-var proposal-counter uint u0)

;; Data Maps
(define-map negotiations uint {
    contract-id: uint,
    initiator: principal,
    status: (string-ascii 20),
    start-date: uint,
    end-date: uint,
    total-proposals: uint
})

(define-map proposals uint {
    negotiation-id: uint,
    proposer: principal,
    proposal-type: (string-ascii 30),
    original-value: (string-ascii 200),
    proposed-value: (string-ascii 200),
    justification: (string-ascii 500),
    status: (string-ascii 20),
    proposal-date: uint,
    response-date: uint
})

(define-map negotiation-participants uint (list 10 principal))

(define-map proposal-responses uint {
    responder: principal,
    response: (string-ascii 20),
    comments: (string-ascii 300),
    response-date: uint
})

;; Read-only functions
(define-read-only (get-negotiation (negotiation-id uint))
    (map-get? negotiations negotiation-id)
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

(define-read-only (get-negotiation-participants (negotiation-id uint))
    (map-get? negotiation-participants negotiation-id)
)

(define-read-only (get-proposal-response (proposal-id uint))
    (map-get? proposal-responses proposal-id)
)

(define-read-only (get-negotiation-count)
    (var-get negotiation-counter)
)

(define-read-only (is-negotiation-active (negotiation-id uint))
    (let ((negotiation (map-get? negotiations negotiation-id)))
        (if (is-some negotiation)
            (is-eq (get status (unwrap-panic negotiation)) "active")
            false))
)

;; Public functions
(define-public (start-negotiation (contract-id uint) (participants (list 10 principal)))
    (let ((new-negotiation-id (+ (var-get negotiation-counter) u1)))
        (begin
            (map-set negotiations new-negotiation-id {
                contract-id: contract-id,
                initiator: tx-sender,
                status: "active",
                start-date: block-height,
                end-date: u0,
                total-proposals: u0
            })

            (map-set negotiation-participants new-negotiation-id participants)
            (var-set negotiation-counter new-negotiation-id)
            (ok new-negotiation-id)))
)

(define-public (submit-proposal
    (negotiation-id uint)
    (proposal-type (string-ascii 30))
    (original-value (string-ascii 200))
    (proposed-value (string-ascii 200))
    (justification (string-ascii 500)))
    (let ((new-proposal-id (+ (var-get proposal-counter) u1))
          (negotiation (unwrap! (map-get? negotiations negotiation-id) ERR_INVALID_NEGOTIATION)))
        (begin
            (asserts! (is-negotiation-active negotiation-id) ERR_NEGOTIATION_CLOSED)

            (map-set proposals new-proposal-id {
                negotiation-id: negotiation-id,
                proposer: tx-sender,
                proposal-type: proposal-type,
                original-value: original-value,
                proposed-value: proposed-value,
                justification: justification,
                status: "pending",
                proposal-date: block-height,
                response-date: u0
            })

            ;; Update negotiation proposal count
            (map-set negotiations negotiation-id
                (merge negotiation { total-proposals: (+ (get total-proposals negotiation) u1) }))

            (var-set proposal-counter new-proposal-id)
            (ok new-proposal-id)))
)

(define-public (respond-to-proposal
    (proposal-id uint)
    (response (string-ascii 20))
    (comments (string-ascii 300)))
    (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR_INVALID_PROPOSAL)))
        (begin
            (asserts! (not (is-eq (get status proposal) "closed")) ERR_NEGOTIATION_CLOSED)

            (map-set proposal-responses proposal-id {
                responder: tx-sender,
                response: response,
                comments: comments,
                response-date: block-height
            })

            (map-set proposals proposal-id
                (merge proposal {
                    status: response,
                    response-date: block-height
                }))

            (ok true)))
)

(define-public (close-negotiation (negotiation-id uint))
    (let ((negotiation (unwrap! (map-get? negotiations negotiation-id) ERR_INVALID_NEGOTIATION)))
        (begin
            (asserts! (is-eq tx-sender (get initiator negotiation)) ERR_UNAUTHORIZED)
            (asserts! (is-negotiation-active negotiation-id) ERR_NEGOTIATION_CLOSED)

            (map-set negotiations negotiation-id
                (merge negotiation {
                    status: "closed",
                    end-date: block-height
                }))

            (ok true)))
)
