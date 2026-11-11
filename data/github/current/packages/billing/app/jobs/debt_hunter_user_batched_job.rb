# typed: strict
# frozen_string_literal: true

# Processes users that need billing in self-re-enqueueing batches,
# avoiding cross-cluster JOINs between users and billing clusters.
#
# Each invocation:
#   1. Users cluster: loads candidate users in a bounded ID range
#      (card billing, valid plan, not suspended).
#   2. Billing cluster: checks which of those users should be excluded
#      (locked customer, Apple IAP, Zuora with payment method).
#   3. Processes only the eligible users.
#
# Re-enqueues itself for the next batch, keeping per-job execution time short.
class DebtHunterUserBatchedJob < BatchedJob
  queue_as :billing

  around_enqueue do |_job, block|
    block.call if GitHub.billing_enabled?
  end

  # Upper bound on the users.id range scanned per batch query.
  QUERY_LIMIT = T.let(100_000, Integer)

  sig { override.params(batch: T::Array[User], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    user_ids = batch.map(&:id)
    excluded_ids = excluded_user_ids(user_ids)
    eligible_users = batch.reject { |u| excluded_ids.include?(u.id) }
    return if eligible_users.empty?

    Billing::Core::DebtHunter.process_user_batch(eligible_users)
  rescue StandardError => e
    GitHub.dogstats.increment("billing.debt_hunter.batched_job.batch_error", tags: ["entity_type:user", "phase:process", "error:#{e.class.name}"])
    GitHub.logger.error("DebtHunterUserBatchedJob batch processing failed", {
      "code.namespace" => self.class.name,
      "offset_item_id" => options[:offset_item_id],
      "batch_size" => batch.size,
      "error.class" => e.class.name,
      "error.message" => e.message,
    })
    # Re-raise so BatchedJob#perform triggers Failbot and ensure_perform
    raise
  end

  sig { override.params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(T::Array[User]) }
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    ActiveRecord::Base.connected_to(role: :reading) do
      user_candidates_in_range(offset_item_id, offset_item_id + QUERY_LIMIT)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a
    end
  rescue StandardError => e
    GitHub.dogstats.increment("billing.debt_hunter.batched_job.batch_error", tags: ["entity_type:user", "phase:query", "error:#{e.class.name}"])
    GitHub.logger.error("DebtHunterUserBatchedJob query failed", {
      "code.namespace" => self.class.name,
      "offset_item_id" => offset_item_id,
      "query_limit" => QUERY_LIMIT,
      "error.class" => e.class.name,
      "error.message" => e.message,
    })
    # Re-raise so BatchedJob#perform triggers Failbot and ensure_perform
    raise
  end

  sig { override.params(batch: T::Array[User], options: T.untyped).returns(T::Boolean) }
  def has_next_batch?(batch, **options)
    max_user_id = options[:max_id].to_i
    if batch.size == BATCH_SIZE
      max_user_id > batch.map(&:id).max
    else
      max_user_id > options[:offset_item_id].to_i + QUERY_LIMIT
    end
  end

  sig { override.params(batch: T::Array[User], args: T.untyped, options: T.untyped).returns(Integer) }
  def next_batch_offset_item_id(batch, *args, **options)
    if batch.size < BATCH_SIZE
      options[:offset_item_id].to_i + QUERY_LIMIT
    else
      batch.map(&:id).max
    end
  end

  sig { override.params(finished_successfully: T::Boolean, options: T.untyped).void }
  def ensure_perform(finished_successfully:, **options)
    return unless finished_successfully
    GitHub.dogstats.increment("billing.debt_hunter.batched_job.completed", tags: ["entity_type:user"])
    GitHub.logger.info("DebtHunterUserBatchedJob completed",
      candidates_scanned: options[:progress] || 0,
      duration_seconds: Time.now.utc - (options[:initial_start] || Time.now.utc),
    )
  end

  private

  # Returns candidate users in a bounded ID range. Queries only users-cluster
  # tables (card billing, valid plan, not suspended, not soft-deleted).
  sig { params(start_id: Integer, end_id: Integer).returns(ActiveRecord::Relation) }
  def user_candidates_in_range(start_id, end_id)
    relation = User
      .where(billing_type: "card")
      .where.not(plan: [nil] + GitHub::Plan.free_names)
      .where("users.billed_on IS NULL OR users.billed_on <= ?", GitHub::Billing.today.to_formatted_s(:db))
      .where(suspended_at: nil)
      .where("users.soft_deleted_at IS NULL")

    relation
      .where("users.id > ?", start_id)
      .where("users.id <= ?", end_id)
  end

  # Returns user IDs that should be excluded from billing. Queries the billing
  # cluster (customer_accounts, customers, plan_subscriptions, payment_methods).
  # Excluded if:
  #   a) Customer billing is locked (customers.locked_at IS NOT NULL)
  #   b) Paying through Apple IAP (apple_transaction_id IS NOT NULL)
  #   c) Paying through Zuora with a valid payment method on file
  sig { params(user_ids: T::Array[Integer]).returns(T::Set[Integer]) }
  def excluded_user_ids(user_ids)
    return Set.new if user_ids.empty?

    CustomerAccount
      .where(user_id: user_ids)
      .joins(EXCLUSION_JOINS)
      .where(EXCLUSION_CONDITIONS)
      .distinct
      .pluck(:user_id)
      .to_set
  end

  EXCLUSION_JOINS = T.let(<<~SQL.squish, String)
    INNER JOIN customers
      ON customers.id = customer_accounts.customer_id
    LEFT OUTER JOIN plan_subscriptions
      ON plan_subscriptions.customer_id = customer_accounts.customer_id
    LEFT OUTER JOIN payment_methods
      ON payment_methods.customer_id = customer_accounts.customer_id
  SQL

  EXCLUSION_CONDITIONS = T.let(<<~SQL.squish, String)
    customers.locked_at IS NOT NULL
    OR plan_subscriptions.apple_transaction_id IS NOT NULL
    OR (
      plan_subscriptions.zuora_subscription_number IS NOT NULL
      AND payment_methods.payment_token IS NOT NULL
      AND payment_methods.payment_token != 'payment-token-cleared'
    )
  SQL

  private_constant :EXCLUSION_JOINS, :EXCLUSION_CONDITIONS
end
