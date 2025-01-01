# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class StartupProgramRenewalEmailJob < BatchedJob
  queue_as :startup_program_renewal_email
  schedule interval: 1.day, condition: -> { GitHub.billing_enabled? }

  retry_on_dirty_exit

  # This method accepts a batch of business and processes them by iterating
  # over each that matches the following criteria and sends them an email:
  # - Belongs to Startup Program
  # - Has invoice that will expire in 30 days
  #
  # @param batch [ActiveRecord::Relation] A batch of business
  # @param args [Array] Arguments passed to the job
  # @param options [Hash] Options passed to the job
  #
  # @return [ActiveRecord::Relation] The next batch of business
  sig { params(batch: ActiveRecord::Relation, args: T.untyped, options: T.untyped).returns(T.untyped) }
  def process_batch(batch, *args, **options)
    batch.each do |business|
      next unless business.part_of_startup_program?
      next if invalid_or_duplicated?(business.startups_program, email_type(business))

      enqueue_email(business)
    end
  end

  private

  sig { params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(ActiveRecord::Relation) }
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    business_with_invoice_within_lookup_window_30_days.or(business_with_invoice_within_lookup_window_3_days).
      where("businesses.id > ?", offset_item_id).
      limit(BATCH_SIZE).
      order(id: :asc)
  end

  sig { params(business: Business).returns(Symbol) }
  def email_type(business)
    startups_program = T.must(business.startups_program)
    case
    when startups_program.year_1? && billing_end_date_in?(business, in_thirty_days)
      :email_30_day_year_1
    when startups_program.year_1? && billing_end_date_in?(business, in_three_days)
      :email_3_day_year_1
    when startups_program.year_2? && billing_end_date_in?(business, in_thirty_days)
      :email_30_day_year_2
    when startups_program.year_2? && billing_end_date_in?(business, in_three_days)
      :email_3_day_year_2
    else
      :invalid
    end
  end

  sig { params(startups_program: BusinessStartupsProgram, email_type: Symbol).returns(T::Boolean) }
  def invalid_or_duplicated?(startups_program, email_type)
    return true if email_type == :invalid

    startups_program.email_sent?(email_type) || false
  end

  sig { params(business: Business).void }
  def enqueue_email(business)
    email_sent!(business)
    StartupProgramMailer.expiration_renewal(business).deliver_later
  end

  sig { params(business: Business).void }
  def email_sent!(business)
    with_write do
      startups_program = T.must(business.startups_program)
      startups_program.emails_sent_at ||= {}
      startups_program.emails_sent_at[email_type(business)] = DateTime.now.utc
      startups_program.save!
    end
  end

  sig { returns(ActiveRecord::Relation) }
  def startup_business_relation
    Business.joins(:customer, :startups_program).where(startups_program: { status: [:year_1, :year_2] })
  end

  sig { returns(ActiveRecord::Relation) }
  def business_with_invoice_within_lookup_window_30_days
    startup_business_relation.where(customer: { billing_end_date: in_thirty_days.all_day })
  end

  sig { returns(ActiveRecord::Relation) }
  def business_with_invoice_within_lookup_window_3_days
    startup_business_relation.where(customer: { billing_end_date: in_three_days.all_day })
  end

  sig { params(business: Business, in_days: Date).returns(T::Boolean) }
  def billing_end_date_in?(business, in_days)
    T.must(business.customer).billing_end_date&.to_date == in_days
  end

  sig { returns(Date) }
  def today
    GitHub::Billing.today.to_date
  end

  sig { returns(Date) }
  def in_thirty_days
    (today + 30.days).to_date
  end

  sig { returns(Date) }
  def in_three_days
    (today + 3.days).to_date
  end
end
