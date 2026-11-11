# typed: true
# frozen_string_literal: true

# Checks if credits have expired for accepted applications and graduates them.
#
# This job runs daily and processes applications in batches.
# When a startups program application's credit has expired, the application_status
# is moved from "accepted" to "graduated".
#
# The job queries the Billing Platform API to check discount expiration dates.
class BusinessStartupsCreditGraduationJob < BatchedJob
  queue_as :business_startups_application_processing
  schedule interval: 1.day, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit
  retry_on ActiveRecord::RecordNotFound, wait: 5.seconds, attempts: 3

  # Process expired credits in batches
  BATCH_SIZE = 100

  sig { override.params(offset_item_id: Integer, options: T.untyped).returns(ActiveRecord::Relation) }
  def next_batch(offset_item_id: 0, **options)
    BusinessStartupsProgram
      .includes(:business)
      .where(application_status: :accepted)
      .where("id > ?", offset_item_id)
      .order(id: :asc)
      .limit(BATCH_SIZE)
  end

  sig { override.params(applications: ActiveRecord::Relation, args: T.untyped, options: T.untyped).void }
  def process_batch(applications, *args, **options)
    return unless FeatureFlag.vexi.enabled?(:gfs_graduate_job, default: false)
    with_write do
      applications.each { |application| check_and_graduate_if_expired(application) }
    end
  end

  private

  sig { params(application: BusinessStartupsProgram).void }
  def check_and_graduate_if_expired(application)
    business = application.business
    return if business.nil?
    return unless business.customer.present?

    # Get all discounts for this business's customer
    response = fetch_discounts_for_business(business)
    if response.is_a?(Billing::Platform::Api::Error)
      GitHub.logger.error(
        "[GFS] Failed to fetch discounts from Billing Platform",
        error_class: response.class.name,
        error_message: response.message,
        business_id: business.id)
      return
    end

    discounts = response[:discounts] || []

    # no discounts, graduate the application
    return graduate_application!(application) if discounts.empty?

    gfs_discounts = find_gfs_discounts(discounts)

    # no GFS discount, graduate the application
    return graduate_application!(application) if gfs_discounts.empty?

    graduate_application!(application) if gfs_discounts.all? { |discount| expired_or_consumed_discount?(discount) }
  end

  sig { params(business: Business).returns(T.untyped) }
  def fetch_discounts_for_business(business)
    customer_id = business.customer_id.to_s
    current_year = Time.current.year
    current_month = Time.current.month

    Billing::Platform::Api::Client.new.get_all_discount_states(
      customer_id: customer_id,
      year: current_year,
      month: current_month,
    )
  end

  sig { params(discounts: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def find_gfs_discounts(discounts)
    discounts.select do |discount|
      discount.dig(:discount, :fundingSource) == Billing::DiscountsDependency::GITHUB_FOR_STARTUPS_FUNDING_SOURCE_STRING.to_sym
    end
  end

  sig { params(discount: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def expired_or_consumed_discount?(discount)
    end_date = discount.dig(:discount, :endDate)
    return true if end_date&.nonzero? && end_date < Time.current.to_i

    current_amount = discount.dig(:currentAmount) || 0
    target_amount = discount.dig(:targetAmount) || 0
    current_amount >= target_amount
  end

  sig { params(application: BusinessStartupsProgram).void }
  def graduate_application!(application)
    application.update!(application_status: :graduated, status: :graduated)
    BusinessStartupsApplicationMailer.graduation_email(application).deliver_later

    GlobalInstrumenter.instrument("business_startups_program.graduated", {
      application: application,
      business: application.business,
      actor: User.ghost,
      reason: "credit_expired",
    })

    GitHub.dogstats.increment("business_startups.application_processing.graduated")

    GitHub.logger.info(
      "[GFS] Startups program credit expired, status moved to graduated",
      application_id: application.id,
      business_id: application.business_id,
    )
  end
end
