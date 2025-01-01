# typed: true

# frozen_string_literal: true

# A `StartupsProgram` represents an "enterprise account" which belongs to the Github for Startups program
class BusinessStartupsProgram < ApplicationRecord::Domain::Users
  belongs_to :business, optional: false

  validates :status, presence: true
  validate :emails_sent_at_keys

  enum :status, [:year_1, :year_2, :graduated, :removed], default: :removed

  EMAIL_TYPES = T.let(
    %i(email_30_day_year_1 email_30_day_year_2 email_3_day_year_1 email_3_day_year_2 welcome).freeze,
    T::Array[Symbol]
  )

  sig { void }
  def emails_sent_at_keys
    return if emails_sent_at.blank?

    errors.add(:emails_sent_at, "invalid key") if (emails_sent_at.symbolize_keys.keys - EMAIL_TYPES).any?
  end

  sig { params(email_type: Symbol).returns(T::Boolean) }
  def email_sent?(email_type)
    return false if emails_sent_at.blank?

    emails_sent_at[email_type.to_s].present?
  end

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
    %i(year_1 year_2 graduated).include?(status&.to_sym)
  end

  def currently_in_the_program?
    BusinessStartupsProgram.currently_in_the_program?(status)
  end

  def send_welcome_email
    return if GitHub.single_business_environment?
    return if already_sent_other_emails?
    return if business_without_owners?
    return unless year_1?

    update_welcome_email_timestamp!
    StartupProgramMailer.welcome(self.business).deliver_later
  end

  private

  def update_welcome_email_timestamp!
    self.emails_sent_at ||= {}
    self.emails_sent_at[:welcome] = DateTime.now.utc
    save!
  end

  def already_sent_other_emails?
    emails_sent_at&.any?
  end

  def business_without_owners?
    business&.owners&.empty?
  end
end
