;; Approval Workflow Contract
;; Manages contract approval processes and workflows

;; Constants
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_INVALID_WORKFLOW (err u401))
(define-constant ERR_WORKFLOW_COMPLETE (err u402))
(define-constant ERR_INVALID_APPROVER (err u403))
(define-constant ERR_ALREADY_APPROVED (err u404))

;; Data Variables
(define-data-var workflow-counter uint u0)

;; Data Maps
(define-map approval-workflows uint {
    contract-id: uint,
    initiator: principal,
    workflow-type: (string-ascii 30),
    status: (string-ascii 20),
    creation-date: uint,
    completion-date: uint,
    required-approvals: uint,
    received-approvals: uint
})

(define-map workflow-approvers uint (list 20 principal))

(define-map approver-responses uint {
    approver: principal,
    approved: bool,
    approval-date: uint,
    comments: (string-ascii 300),
    conditions: (string-ascii 500)
})

(define-map workflow-steps uint {
    step-number: uint,
    step-name: (string-ascii 50),
    required-role: (string-ascii 30),
    completed: bool,
    completion-date: uint,
    approver: (optional principal)
})

;; Read-only functions
(define-read-only (get-workflow (workflow-id uint))
    (map-get? approval-workflows workflow-id)
)

(define-read-only (get-workflow-approvers (workflow-id uint))
    (map-get? workflow-approvers workflow-id)
)

(define-read-only (get-approver-response (workflow-id uint) (approver principal))
    (map-get? approver-responses (+ (* workflow-id u1000) (mod (unwrap-panic (principal-to-uint approver)) u1000)))
)

(define-read-only (get-workflow-step (workflow-id uint) (step-number uint))
    (map-get? workflow-steps (+ (* workflow-id u100) step-number))
)

(define-read-only (is-workflow-complete (workflow-id uint))
    (let ((workflow (map-get? approval-workflows workflow-id)))
        (if (is-some workflow)
            (>= (get received-approvals (unwrap-panic workflow))
                (get required-approvals (unwrap-panic workflow)))
            false))
)

(define-read-only (get-workflow-count)
    (var-get workflow-counter)
)

;; Helper function to convert principal to uint (simplified)
(define-private (principal-to-uint (p principal))
    (ok u1) ;; Simplified implementation
)

;; Public functions
(define-public (create-approval-workflow
    (contract-id uint)
    (workflow-type (string-ascii 30))
    (approvers (list 20 principal))
    (required-approvals uint))
    (let ((new-workflow-id (+ (var-get workflow-counter) u1)))
        (begin
            (asserts! (> required-approvals u0) ERR_INVALID_WORKFLOW)
            (asserts! (<= required-approvals (len approvers)) ERR_INVALID_WORKFLOW)

            (map-set approval-workflows new-workflow-id {
                contract-id: contract-id,
                initiator: tx-sender,
                workflow-type: workflow-type,
                status: "pending",
                creation-date: block-height,
                completion-date: u0,
                required-approvals: required-approvals,
                received-approvals: u0
            })

            (map-set workflow-approvers new-workflow-id approvers)
            (var-set workflow-counter new-workflow-id)
            (ok new-workflow-id)))
)

(define-public (submit-approval
    (workflow-id uint)
    (approved bool)
    (comments (string-ascii 300))
    (conditions (string-ascii 500)))
    (let ((workflow (unwrap! (map-get? approval-workflows workflow-id) ERR_INVALID_WORKFLOW))
          (approver-key (+ (* workflow-id u1000) (mod (unwrap-panic (principal-to-uint tx-sender)) u1000))))
        (begin
            (asserts! (not (is-workflow-complete workflow-id)) ERR_WORKFLOW_COMPLETE)

            ;; Check if approver is authorized
            (let ((approvers (unwrap! (map-get? workflow-approvers workflow-id) ERR_INVALID_WORKFLOW)))
                (asserts! (is-some (index-of approvers tx-sender)) ERR_INVALID_APPROVER))

            ;; Check if already approved
            (asserts! (is-none (map-get? approver-responses approver-key)) ERR_ALREADY_APPROVED)

            ;; Record the approval
            (map-set approver-responses approver-key {
                approver: tx-sender,
                approved: approved,
                approval-date: block-height,
                comments: comments,
                conditions: conditions
            })

            ;; Update workflow if approved
            (if approved
                (let ((new-approval-count (+ (get received-approvals workflow) u1)))
                    (begin
                        (map-set approval-workflows workflow-id
                            (merge workflow { received-approvals: new-approval-count }))

                        ;; Check if workflow is now complete
                        (if (>= new-approval-count (get required-approvals workflow))
                            (map-set approval-workflows workflow-id
                                (merge workflow {
                                    status: "approved",
                                    completion-date: block-height,
                                    received-approvals: new-approval-count
                                }))
                            true)))
                true)

            (ok true)))
)

(define-public (reject-workflow (workflow-id uint) (reason (string-ascii 300)))
    (let ((workflow (unwrap! (map-get? approval-workflows workflow-id) ERR_INVALID_WORKFLOW)))
        (begin
            (asserts! (is-eq tx-sender (get initiator workflow)) ERR_UNAUTHORIZED)
            (asserts! (not (is-workflow-complete workflow-id)) ERR_WORKFLOW_COMPLETE)

            (map-set approval-workflows workflow-id
                (merge workflow {
                    status: "rejected",
                    completion-date: block-height
                }))

            (ok true)))
)

(define-public (add-workflow-step
    (workflow-id uint)
    (step-number uint)
    (step-name (string-ascii 50))
    (required-role (string-ascii 30)))
    (let ((workflow (unwrap! (map-get? approval-workflows workflow-id) ERR_INVALID_WORKFLOW)))
        (begin
            (asserts! (is-eq tx-sender (get initiator workflow)) ERR_UNAUTHORIZED)

            (map-set workflow-steps (+ (* workflow-id u100) step-number) {
                step-number: step-number,
                step-name: step-name,
                required-role: required-role,
                completed: false,
                completion-date: u0,
                approver: none
            })

            (ok true)))
)
