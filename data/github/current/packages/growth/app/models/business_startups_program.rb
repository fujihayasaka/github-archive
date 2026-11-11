# typed: true

# frozen_string_literal: true

# A `StartupsProgram` represents an "enterprise account" which belongs to the Github for Startups program
class BusinessStartupsProgram < ApplicationRecord::Domain::Users
  belongs_to :business, optional: false

  validates :status, presence: true

  # year_1 and year_2 fields are deprecated
  enum :status, [:year_1, :year_2, :graduated, :removed, :accepted], default: :removed
  enum :application_status, [:processing, :pending_review, :accepted, :rejected, :graduated], prefix: true

  sig { params(business: T.nilable(Business), status: T.any(String, Symbol)).returns(T.nilable(BusinessStartupsProgram)) }
  def self.create_or_update!(business, status)
    return unless business

    if startups_program = business.startups_program
      startups_program.update(status:)
      startups_program
    else
      create!(business: business, status: status) if currently_in_the_program?(status.to_s)
    end

  end

  sig { params(status: T.nilable(String)).returns(T::Boolean) }
  def self.currently_in_the_program?(status)
    %i(year_1 year_2 graduated accepted).include?(status&.to_sym)
  end

  def currently_in_the_program?
    BusinessStartupsProgram.currently_in_the_program?(status)
  end

  sig { returns(T.nilable(User)) }
  def applicant
    user_id = application_data&.dig("user_id") || application_data&.dig(:user_id)
    return if user_id.blank?

    User.find_by(id: user_id)
  end

  sig { returns(T.nilable(String)) }
  def applicant_email
    application_data&.dig("email") || application_data&.dig(:email)
  end

  # Apply discount credit to the business for the startups program
  #
  # amount - Billing::Money amount to credit
  # start_date - Time when the discount becomes active
  # end_date - Time when the discount expires
  #
  # Returns a hash with :success and either :discount_uuid or :error_message
  sig do
    params(
      amount: Billing::Money,
      start_date: Time,
      end_date: Time
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def apply_billing_credit(amount:, start_date:, end_date:)
    BusinessStartupsProgram::ApplyBillingCredit.perform(
      business: business,
      amount: amount,
      start_date: start_date,
      end_date: end_date
    )
  end

  sig { params(actor: T.nilable(User)).void }
  def accept!(actor: nil)
    update!(
      application_status: :accepted,
      status: :accepted,
      accepted_at: Time.current,
      processed_at: Time.current
    )
  end

  sig { params(rejection_reason: String, actor: T.nilable(User)).void }
  def reject!(rejection_reason:, actor: nil)
    update!(
      application_status: :rejected,
      status: :removed,
      rejected_at: Time.current,
      processed_at: Time.current,
      rejection_reason: rejection_reason
    )
  end

  sig { params(rejection_reason: String, actor: T.nilable(User)).void }
  def set_pending_review!(rejection_reason:, actor: nil)
    update!(
      application_status: :pending_review,
      processed_at: Time.current,
      rejection_reason: rejection_reason
    )
  end
end
