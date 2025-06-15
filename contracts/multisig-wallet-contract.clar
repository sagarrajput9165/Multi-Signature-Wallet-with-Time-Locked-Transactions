;; Multi-Signature Wallet with Time-Locked Transactions
;; A simple contract that requires multiple signatures and enforces time delays

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-insufficient-signatures (err u101))
(define-constant err-timelock-not-expired (err u102))

;; Data Variables
(define-data-var required-signatures uint u2)
(define-data-var timelock-duration uint u144) ;; ~24 hours in blocks

;; Data Maps
(define-map authorized-signers principal bool)
(define-map pending-transactions 
  { tx-id: uint } 
  { 
    recipient: principal, 
    amount: uint, 
    signatures: uint, 
    created-at: uint,
    executed: bool 
  })

(define-map transaction-signatures { tx-id: uint, signer: principal } bool)
(define-data-var next-tx-id uint u1)

;; Initialize authorized signers (contract owner is automatically authorized)
(map-set authorized-signers contract-owner true)

;; Function to propose a new transaction
(define-public (propose-transaction (recipient principal) (amount uint))
  (let ((tx-id (var-get next-tx-id)))
    (asserts! (default-to false (map-get? authorized-signers tx-sender)) err-not-authorized)
    (map-set pending-transactions 
      { tx-id: tx-id }
      { 
        recipient: recipient, 
        amount: amount, 
        signatures: u1, 
        created-at: stacks-block-height,
        executed: false 
      })
    (map-set transaction-signatures { tx-id: tx-id, signer: tx-sender } true)
    (var-set next-tx-id (+ tx-id u1))
    (ok tx-id)))

;; Function to sign a pending transaction
(define-public (sign-transaction (tx-id uint))
  (let ((tx-data (unwrap! (map-get? pending-transactions { tx-id: tx-id }) err-not-authorized)))
    (asserts! (default-to false (map-get? authorized-signers tx-sender)) err-not-authorized)
    (asserts! (is-none (map-get? transaction-signatures { tx-id: tx-id, signer: tx-sender })) err-not-authorized)
    (asserts! (not (get executed tx-data)) err-not-authorized)
    (map-set transaction-signatures { tx-id: tx-id, signer: tx-sender } true)
    (map-set pending-transactions 
      { tx-id: tx-id }
      (merge tx-data { signatures: (+ (get signatures tx-data) u1) }))
    (ok true)))

;; Function to execute a transaction (requires sufficient signatures and time delay)
(define-public (execute-transaction (tx-id uint))
  (let ((tx-data (unwrap! (map-get? pending-transactions { tx-id: tx-id }) err-not-authorized)))
    (asserts! (>= (get signatures tx-data) (var-get required-signatures)) err-insufficient-signatures)
    (asserts! (>= stacks-block-height (+ (get created-at tx-data) (var-get timelock-duration))) err-timelock-not-expired)
    (asserts! (not (get executed tx-data)) err-not-authorized)
    (map-set pending-transactions 
      { tx-id: tx-id }
      (merge tx-data { executed: true }))
    (stx-transfer? (get amount tx-data) (as-contract tx-sender) (get recipient tx-data))))