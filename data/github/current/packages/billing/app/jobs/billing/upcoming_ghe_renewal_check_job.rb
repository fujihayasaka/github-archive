# typed: strict
# frozen_string_literal: true

class Billing::UpcomingGheRenewalCheckJob < TimedJob
  # Scheduled job, runs every day

  BATCH_LIMIT = 100
  queue_as :billing_renewal_notice
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig do
    override
    .params(
      args: T.untyped,
      offset_id: Integer,
      kwargs: T.untyped
    )
    .returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def fetch_batch(*args, offset_id:, **kwargs)
    Business
      .self_renewal_eligible
      .with_term_end_date(..30.days.from_now)
      .where(::Business.arel_table[:id].gt(offset_id))
      .order(:id)
      .limit(BATCH_LIMIT)
  end

  sig do
    override
    .params(
      args: T.untyped,
      item: T.untyped,
      kwargs: T.untyped
    )
    .void
  end
  def process_item(*args, item:, **kwargs)
    business = T.let(item, Business)

    # filter out businesses that have already gone through the renewal
    return if business.renewal_already_requested?
    return unless business.sales_managed_subscription_self_serve_eligible?

    # filter out businesses that have overdue invoices
    return if business.feature_flag_enabled_or_raise?(:ghe_sales_serve_overdue) && business.past_due_invoice? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    business.admins.each do |admin|
      notice = GlobalNoticeNext.new(viewer: admin)
      GlobalNotice.throttle_writes { notice.set_notice(:upcoming_ghe_renewal) }
    end
  end
end
