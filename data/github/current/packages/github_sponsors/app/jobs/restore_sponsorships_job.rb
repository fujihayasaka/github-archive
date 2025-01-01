# typed: strict
# frozen_string_literal: true

class RestoreSponsorshipsJob < ApplicationJob
  extend T::Sig
  include GitHub::Billing::ZuoraRateLimitHandler
  include GitHub::Memoizer
  queue_as :restore_sponsorships

  retry_on_dirty_exit

  ALL_RETRYABLE_ERRORS = T.let(::Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ERRORS +
    ::Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ERRORS +
    ::Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ERRORS +
    [Zuorest::TooManyRequestsError], T::Array[T.class_of(StandardError)])

  NON_REPORTABLE_ERRORS = T.let(ALL_RETRYABLE_ERRORS.without(Zuorest::GatewayTimeoutError), T::Array[T.class_of(StandardError)])

  Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ERRORS.each do |error|
    retry_on(
      error,
      wait: :polynomially_longer,
      attempts: ::Billing::PlanSubscription::SynchronizationEvents::RETRYABLE_ATTEMPTS
    )
  end

  Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ERRORS.each do |error|
    retry_on(
      error,
      wait: :polynomially_longer,
      attempts: ::Billing::PlanSubscription::SynchronizationEvents::EXTRA_RETRYABLE_ATTEMPTS
    )
  end

  Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ERRORS.each do |error|
    retry_on(
      error,
      wait: 2.hours,
      attempts: ::Billing::PlanSubscription::SynchronizationEvents::DELAYED_RETRYABLE_ATTEMPTS
    )
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, RestoreSponsorshipsJob)
    zuora_rate_limit_handler(self, error)
  end

  sig { params(sponsor: GitHubSponsors::Types::Sponsor, sponsorships: T::Array[Sponsorship], actor: User).void }
  def perform(sponsor:, sponsorships:, actor:)
    @sponsor = T.let(sponsor, T.nilable(GitHubSponsors::Types::Sponsor))
    @sponsorships = T.let(sponsorships, T.nilable(T::Array[Sponsorship]))
    @actor = T.let(actor, T.nilable(User))

    validate_arguments
    general_plan_sub = sponsor.plan_subscription

    with_write do
      with_lock_for(sponsor) do
        restore_sponsorships
        result = synchronize_plan_subscription
        zero_out_invoices_generated_by(result)
      end
    end
  rescue => error # rubocop:todo Lint/GenericRescue
    Failbot.report(error) unless NON_REPORTABLE_ERRORS.include?(error.class)
    raise
  end

  private

  sig { returns GitHubSponsors::Types::Sponsor }
  def sponsor
    T.must_because(@sponsor) { "only called after #perform makes it non-nil" }
  end

  sig { returns T::Array[Sponsorship] }
  def sponsorships
    T.must_because(@sponsorships) { "only called after #perform makes it non-nil" }
  end

  sig { returns User }
  def actor
    T.must_because(@actor) { "only called after #perform makes it non-nil" }
  end

  sig { void }
  def validate_arguments
    if !GitHub.sponsors_enabled? || !GitHub.billing_enabled?
      raise ArgumentError, "Requires billing and sponsors to be enabled in the environment"
    end

    if sponsor.blank? || sponsorships.blank?
      raise ArgumentError, "Requires a sponsor and an array of their sponsorships to restore."
    end

    GitHub::PrefillAssociations.prefill_associations(sponsorships,
      [:sponsor, { subscription_item: :plan_subscription }]
    )

    if sponsorships.any? { |sponsorship| sponsorship.sponsor != sponsor }
      raise ArgumentError, "Requires all sponsorships to belong to the sponsor"
    end

    if sponsorships.map(&:plan_subscription).uniq.compact.size != 1
      raise ArgumentError, "Requires all sponsorships to use the same plan subscription"
    end
  end

  # We want to mark all Sponsorship records as active
  # But we only want to re-activate recurring Billing::SubscriptionItems since Billing::SubscriptionItems
  # for one-time tiers are deactivated shortly after payment since they do not recur
  sig { void }
  def restore_sponsorships
    Sponsorship.where(id: sponsorships).update_all(active: true)
    Sponsorship.where(id: expired_one_time_sponsorships).update_all(expires_at: Sponsorship.expiration_time)
    Billing::SubscriptionItem.where(id: subscription_item_ids).update_all(quantity: 1)
    instrument_sponsorships_restored
    SponsorsActivity.create(sponsors_activities_attrs)
  end

  sig { returns T::Array[Sponsorship] }
  memoize def one_time_sponsorships
    sponsorships.select(&:one_time_payment?)
  end

  sig { returns T::Array[Sponsorship] }
  def expired_one_time_sponsorships
    one_time_sponsorships.select(&:expired?)
  end

  sig { returns T::Array[Integer] }
  def subscription_item_ids
    sponsorships.select(&:recurring_payment?).map(&:subscription_item_id).compact +
      stale_unpaid_one_time_sponsorships.map(&:subscription_item_id).compact
  end

  sig { returns T::Array[Sponsorship] }
  def stale_unpaid_one_time_sponsorships
    one_time_sponsorships.reject(&:paid?).select do |sponsorship|
      subscription_item = sponsorship.subscription_item
      subscription_item&.stale_one_time_sponsorship?
    end
  end

  sig { returns Billing::PlanSubscription }
  def plan_subscription
    first_sponsorship = T.must_because(sponsorships.first) { "#validate_arguments ensures not an empty list" }
    T.must_because(first_sponsorship.plan_subscription) do
      "#validate_arguments ensures non-nil plan subscription for every sponsorship"
    end
  end

  sig { void }
  def instrument_sponsorships_restored
    sponsorships.each { |sponsorship| sponsorship.instrument_restoration(actor: actor) }
  end

  sig { returns T::Array[T::Hash[Symbol, T.untyped]] }
  def sponsors_activities_attrs
    sponsorships.map do |sponsorship|
      {
        timestamp: Time.now,
        sponsorable_id: sponsorship.sponsorable_id,
        sponsor_id: sponsor.id,
        sponsors_tier_id: sponsorship.subscribable_id,
        action: :new_sponsorship,
        sponsorable_metadata: {},
        repository_id: sponsorship.sponsors_only_repository&.id,
      }
    end
  end

  sig { params(user: GitHubSponsors::Types::Sponsor, block: T.proc.void).void }
  def with_lock_for(user, &block)
    Billing::Zuora::Webhooks::InvoicePosted.lock_processing(account: user) do
      plan_subscription.with_lock do
        yield
      end
    end
  end

  sig { returns GitHub::Billing::Result }
  def synchronize_plan_subscription
    plan_subscription.synchronize(
      attempts_per_exception: exception_executions,
      collect: false,
      apply_credit_balance: false,
    )
  end

  sig { params(result: GitHub::Billing::Result).void }
  def zero_out_invoices_generated_by(result)
    external_result = result.external_result
    invoice_id = external_result["invoiceId"] if external_result.present?
    return unless invoice_id.present?

    invoice = ::Billing::Zuora::Invoice.new(invoice_id)
    ::Billing::Zuora::ZeroOutInvoice.run(invoice: invoice)
  rescue Zuorest::Error => error
    # We will need to clean up any invoices that fail to zero out before the next billing run,
    # so we always report these errors
    Failbot.report(error)
    raise error
  end
end
