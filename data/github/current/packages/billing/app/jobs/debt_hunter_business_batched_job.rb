# typed: strict
# frozen_string_literal: true

# Processes businesses that need billing in self-re-enqueueing batches,
# using customer_accounts instead of the deprecated businesses.customer_id.
#
# Avoids cross-cluster JOINs by:
#   1. Billing cluster: query customer_accounts in a bounded ID range, JOIN
#      customers/plan_subscriptions/payment_methods (same cluster) to find
#      eligible customer_accounts.
#   2. Users cluster: load matching businesses and process charges.
#
# Each invocation handles one batch and re-enqueues itself for the next,
# keeping per-job execution time short.
class DebtHunterBusinessBatchedJob < BatchedJob
  queue_as :billing

  around_enqueue do |_job, block|
    block.call if GitHub.billing_enabled?
  end

  # Upper bound on the customer_accounts.id range scanned per batch query.
  # Keeps query cost bounded even when IDs are sparse.
  QUERY_LIMIT = T.let(100_000, Integer)

  sig { override.params(batch: T::Array[CustomerAccount], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    business_ids = batch.map(&:billable_entity_id).uniq
    businesses = ActiveRecord::Base.connected_to(role: :reading) do
      Business
        .where(id: business_ids, trial_expires_at: nil, downgraded_at: nil)
        .to_a
    end
    return if businesses.empty?

    Billing::Core::DebtHunter.process_business_batch(businesses)
  rescue StandardError => e
    GitHub.dogstats.increment("billing.debt_hunter.batched_job.batch_error", tags: ["entity_type:business", "phase:process", "error:#{e.class.name}"])
    GitHub.logger.error("DebtHunterBusinessBatchedJob batch processing failed", {
      "code.namespace" => self.class.name,
      "offset_item_id" => options[:offset_item_id],
      "batch_size" => batch.size,
      "error.class" => e.class.name,
      "error.message" => e.message,
    })
    # Re-raise so BatchedJob#perform triggers Failbot and ensure_perform
    raise
  end

  sig { override.params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(T::Array[CustomerAccount]) }
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    ActiveRecord::Base.connected_to(role: :reading) do
      CustomerAccount
        .where(billable_entity_type: "Business")
        .where("customer_accounts.id > ?", offset_item_id)
        .where("customer_accounts.id <= ?", offset_item_id + QUERY_LIMIT)
        .joins(<<~SQL.squish)
          INNER JOIN customers
            ON customers.id = customer_accounts.customer_id
          LEFT OUTER JOIN plan_subscriptions
            ON plan_subscriptions.customer_id = customer_accounts.customer_id
          LEFT OUTER JOIN payment_methods
            ON payment_methods.customer_id = customer_accounts.customer_id
        SQL
        .where(customers: { billing_type: "card" })
        .where(
          "customers.billing_end_date IS NULL OR customers.billing_end_date <= ?",
          GitHub::Billing.today.to_formatted_s(:db),
        )
        .where("plan_subscriptions.apple_transaction_id IS NULL")
        .where(<<~SQL.squish)
          plan_subscriptions.zuora_subscription_number IS NULL
          OR plan_subscriptions.zuora_subscription_number IS NOT NULL
          AND (payment_methods.payment_token IS NULL
            OR payment_methods.payment_token = 'payment-token-cleared')
        SQL
        .distinct
        .select("customer_accounts.*")
        .order("customer_accounts.id")
        .limit(BATCH_SIZE)
        .to_a
    end
  rescue StandardError => e
    GitHub.dogstats.increment("billing.debt_hunter.batched_job.batch_error", tags: ["entity_type:business", "phase:query", "error:#{e.class.name}"])
    GitHub.logger.error("DebtHunterBusinessBatchedJob query failed", {
      "code.namespace" => self.class.name,
      "offset_item_id" => offset_item_id,
      "query_limit" => QUERY_LIMIT,
      "error.class" => e.class.name,
      "error.message" => e.message,
    })
    # Re-raise so BatchedJob#perform triggers Failbot and ensure_perform
    raise
  end

  sig { override.params(batch: T::Array[CustomerAccount], options: T.untyped).returns(T::Boolean) }
  def has_next_batch?(batch, **options)
    max_ca_id = options[:max_id].to_i
    if batch.size == BATCH_SIZE
      max_ca_id > batch.map(&:id).max
    else
      max_ca_id > options[:offset_item_id].to_i + QUERY_LIMIT
    end
  end

  sig { override.params(batch: T::Array[CustomerAccount], args: T.untyped, options: T.untyped).returns(Integer) }
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
    GitHub.dogstats.increment("billing.debt_hunter.batched_job.completed", tags: ["entity_type:business"])
    GitHub.logger.info("DebtHunterBusinessBatchedJob completed",
      candidates_scanned: options[:progress] || 0,
      duration_seconds: Time.now.utc - (options[:initial_start] || Time.now.utc),
    )
  end
end
