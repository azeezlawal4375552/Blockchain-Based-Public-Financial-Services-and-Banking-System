;; Credit Union and Cooperative Banking Contract
;; Supports member-owned financial institutions

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-NOT-MEMBER (err u401))
(define-constant ERR-INSUFFICIENT-BALANCE (err u402))
(define-constant ERR-INVALID-AMOUNT (err u403))
(define-constant ERR-ALREADY-MEMBER (err u404))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u405))
(define-constant ERR-ALREADY-VOTED (err u406))

;; Data Variables
(define-data-var member-counter uint u0)
(define-data-var proposal-counter uint u0)
(define-data-var total-assets uint u0)
(define-data-var dividend-rate uint u500) ;; 5% annual dividend

;; Data Maps
(define-map members
  { member: principal }
  {
    member-id: uint,
    join-date: uint,
    share-balance: uint,
    savings-balance: uint,
    voting-power: uint,
    status: (string-ascii 20)
  }
)

(define-map member-transactions
  { member: principal, transaction-id: uint }
  {
    transaction-type: (string-ascii 20),
    amount: uint,
    timestamp: uint,
    description: (string-ascii 100)
  }
)

(define-map governance-proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposal-type: (string-ascii 50),
    votes-for: uint,
    votes-against: uint,
    voting-deadline: uint,
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map member-votes
  { proposal-id: uint, member: principal }
  {
    vote: bool,
    voting-power-used: uint,
    vote-timestamp: uint
  }
)

(define-map dividend-distributions
  { member: principal, year: uint }
  {
    dividend-amount: uint,
    distribution-date: uint,
    share-balance-basis: uint
  }
)

;; Public Functions

;; Join credit union as member
(define-public (join-credit-union (initial-share-purchase uint))
  (let
    (
      (member-id (+ (var-get member-counter) u1))
      (existing-member (map-get? members { member: tx-sender }))
    )
    (asserts! (is-none existing-member) ERR-ALREADY-MEMBER)
    (asserts! (>= initial-share-purchase u100) ERR-INVALID-AMOUNT) ;; Minimum share purchase

    (map-set members
      { member: tx-sender }
      {
        member-id: member-id,
        join-date: block-height,
        share-balance: initial-share-purchase,
        savings-balance: u0,
        voting-power: (calculate-voting-power initial-share-purchase),
        status: "active"
      }
    )

    (var-set member-counter member-id)
    (var-set total-assets (+ (var-get total-assets) initial-share-purchase))

    (record-transaction tx-sender "share-purchase" initial-share-purchase "Initial membership shares")
    (ok member-id)
  )
)

;; Deposit to savings account
(define-public (deposit-savings (amount uint))
  (let
    (
      (member (unwrap! (map-get? members { member: tx-sender }) ERR-NOT-MEMBER))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-eq (get status member) "active") ERR-NOT-AUTHORIZED)

    (map-set members
      { member: tx-sender }
      (merge member { savings-balance: (+ (get savings-balance member) amount) })
    )

    (var-set total-assets (+ (var-get total-assets) amount))
    (record-transaction tx-sender "deposit" amount "Savings deposit")
    (ok true)
  )
)

;; Withdraw from savings account
(define-public (withdraw-savings (amount uint))
  (let
    (
      (member (unwrap! (map-get? members { member: tx-sender }) ERR-NOT-MEMBER))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= (get savings-balance member) amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (is-eq (get status member) "active") ERR-NOT-AUTHORIZED)

    (map-set members
      { member: tx-sender }
      (merge member { savings-balance: (- (get savings-balance member) amount) })
    )

    (var-set total-assets (- (var-get total-assets) amount))
    (record-transaction tx-sender "withdrawal" amount "Savings withdrawal")
    (ok true)
  )
)

;; Purchase additional shares
(define-public (purchase-shares (amount uint))
  (let
    (
      (member (unwrap! (map-get? members { member: tx-sender }) ERR-NOT-MEMBER))
      (new-share-balance (+ (get share-balance member) amount))
      (new-voting-power (calculate-voting-power new-share-balance))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-eq (get status member) "active") ERR-NOT-AUTHORIZED)

    (map-set members
      { member: tx-sender }
      (merge member {
        share-balance: new-share-balance,
        voting-power: new-voting-power
      })
    )

    (var-set total-assets (+ (var-get total-assets) amount))
    (record-transaction tx-sender "share-purchase" amount "Additional share purchase")
    (ok true)
  )
)

;; Create governance proposal (members only)
(define-public (create-proposal
  (title (string-ascii 100))
  (description (string-ascii 500))
  (proposal-type (string-ascii 50)))
  (let
    (
      (proposal-id (+ (var-get proposal-counter) u1))
      (member (unwrap! (map-get? members { member: tx-sender }) ERR-NOT-MEMBER))
    )
    (asserts! (is-eq (get status member) "active") ERR-NOT-AUTHORIZED)

    (map-set governance-proposals
      { proposal-id: proposal-id }
      {
        proposer: tx-sender,
        title: title,
        description: description,
        proposal-type: proposal-type,
        votes-for: u0,
        votes-against: u0,
        voting-deadline: (+ block-height u1008), ;; 1 week voting period
        status: "active",
        created-at: block-height
      }
    )

    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

;; Vote on proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let
    (
      (proposal (unwrap! (map-get? governance-proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
      (member (unwrap! (map-get? members { member: tx-sender }) ERR-NOT-MEMBER))
      (existing-vote (map-get? member-votes { proposal-id: proposal-id, member: tx-sender }))
    )
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    (asserts! (is-eq (get status member) "active") ERR-NOT-AUTHORIZED)
    (asserts! (< block-height (get voting-deadline proposal)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status proposal) "active") ERR-NOT-AUTHORIZED)

    (map-set member-votes
      { proposal-id: proposal-id, member: tx-sender }
      {
        vote: vote-for,
        voting-power-used: (get voting-power member),
        vote-timestamp: block-height
      }
    )

    (if vote-for
      (map-set governance-proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-for: (+ (get votes-for proposal) (get voting-power member)) }))
      (map-set governance-proposals
        { proposal-id: proposal-id }
        (merge proposal { votes-against: (+ (get votes-against proposal) (get voting-power member)) }))
    )

    (ok true)
  )
)

;; Distribute dividends (admin only)
(define-public (distribute-dividends (year uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    ;; This would iterate through all members in a real implementation
    ;; For now, it's a placeholder that sets the dividend rate
    (var-set dividend-rate (var-get dividend-rate))
    (ok true)
  )
)

;; Read-only Functions

;; Get member details
(define-read-only (get-member (member principal))
  (map-get? members { member: member })
)

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id })
)

;; Get member vote
(define-read-only (get-member-vote (proposal-id uint) (member principal))
  (map-get? member-votes { proposal-id: proposal-id, member: member })
)

;; Get total assets
(define-read-only (get-total-assets)
  (var-get total-assets)
)

;; Get dividend rate
(define-read-only (get-dividend-rate)
  (var-get dividend-rate)
)

;; Get member counter
(define-read-only (get-member-counter)
  (var-get member-counter)
)

;; Private Functions

;; Calculate voting power based on share balance
(define-private (calculate-voting-power (share-balance uint))
  (if (<= share-balance u1000)
    u1
    (if (<= share-balance u5000)
      u2
      (if (<= share-balance u10000)
        u3
        u5
      )
    )
  )
)

;; Record member transaction
(define-private (record-transaction
  (member principal)
  (transaction-type (string-ascii 20))
  (amount uint)
  (description (string-ascii 100)))
  (map-set member-transactions
    { member: member, transaction-id: block-height }
    {
      transaction-type: transaction-type,
      amount: amount,
      timestamp: block-height,
      description: description
    }
  )
)
