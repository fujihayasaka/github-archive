# typed: true
# frozen_string_literal: true

class BusinessStartupsProgram::Application
  include ActiveModel::Model

  FORM_PARAMS = T.let(%i[
    business_id
    partner_id
    company_name
    first_name
    last_name
    email
    role
    company_website
    company_overview
    industry
    country
    latest_funding_round
    funding_raised
    crunchbase_link
    opt_in_checkbox
    tos_checkbox
    terms_checkbox
  ].freeze, T::Array[Symbol])

  STARTUPS_PROGRAM_BUSINESS_MAX_AGE = T.let(90.days, ActiveSupport::Duration)

  PERSONAL_EMAIL_DOMAINS = T.let(
    UserEmail::MarketingDependency::PERSONAL_DOMAINS
    .product(UserEmail::MarketingDependency::TOP_LEVEL_DOMAINS.map { |tld| ".#{tld}" })
    .map(&:join).freeze,
  T::Array[String])

  attr_accessor :user
  attr_accessor :business
  FORM_PARAMS.each { |param| attr_accessor param }

  validates_presence_of :user
  validates_presence_of :business
  FORM_PARAMS.each do |param|
    validates_presence_of param
    validates_length_of param, maximum: 1000
  end

  validate :partner_id_must_be_valid

  validates_format_of :crunchbase_link, with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL"

  validates_acceptance_of :opt_in_checkbox, accept: ["True"]
  validates_acceptance_of :tos_checkbox, accept: ["True"]
  validates_acceptance_of :terms_checkbox, accept: ["True"]

  validate :email_must_be_verified_company_email
  validate :business_must_be_eligible

  sig { params(link: T.nilable(String)).returns(T::Boolean) }
  def self.crunchbase_url?(link)
    link.to_s.match?(/crunchbase\.com/i)
  end

  sig { params(business: Business).returns(T::Array[String]) }
  def self.business_ineligibility_reasons(business)
    reasons = []

    if business.startups_program.present?
      reasons << "existing application"
    end

    if business.created_at.present? && business.created_at < STARTUPS_PROGRAM_BUSINESS_MAX_AGE.ago
      reasons << "too old"
    end

    reasons << "volume account" unless business.metered_ghe?
    reasons << "no payment method" unless business.has_valid_payment_method?
    reasons << "payment method locked" if business.billing_disabled_by_authorization_failure?

    reasons
  end

  sig { params(user: User).returns(T::Array[String]) }
  def self.company_emails(user)
    user.emails.verified.map(&:email).reject do |email|
      email.to_s.split("@").last.in?(PERSONAL_EMAIL_DOMAINS)
    end
  end

  private

  def email_must_be_verified_company_email
    return if user.nil?

    email_value = T.unsafe(self).email.to_s
    return if email_value.empty? # also checked by validates_presence_of

    return if self.class.company_emails(user).include?(email_value)

    errors.add(:email, :invalid)
  end

  def business_must_be_eligible
    return if business.nil? # also checked by validates_presence_of

    reasons = self.class.business_ineligibility_reasons(business)
    return if reasons.empty?

    errors.add(:business_id, "is invalid: #{reasons.join(", ")}")
  end

  def partner_id_must_be_valid
    pid = T.unsafe(self).partner_id.to_s
    canonical_id = BusinessStartupsProgram::Partners.canonical(pid)
    if canonical_id
      T.unsafe(self).partner_id = canonical_id
    else
      errors.add(:partner_id, :inclusion)
    end
  end
end
