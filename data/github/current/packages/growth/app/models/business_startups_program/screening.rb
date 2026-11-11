# typed: strict
# frozen_string_literal: true

class BusinessStartupsProgram::Screening
  ABUSE_RATE_LIMIT_KEY_PREFIX = T.let("business_startups_screening_abuse", String)
  ABUSE_RATE_LIMIT_MAX = T.let(3, Integer)
  ABUSE_RATE_LIMIT_TTL = T.let(24.hours.to_i, Integer)

  REJECTION_DOMAIN_EMAIL_MISMATCH = T.let("domain_email_mismatch", String)
  REJECTION_MISSING_CRUNCHBASE = T.let("missing_crunchbase", String)

  sig { params(application: BusinessStartupsProgram).returns(T.nilable(String)) }
  def self.call(application)
    new(application).send(:screen)
  end

  private

  sig { params(application: BusinessStartupsProgram).void }
  def initialize(application)
    @application = T.let(application, BusinessStartupsProgram)

    business = application.business
    raise ArgumentError, "application must have a business" if business.nil?

    @business = T.let(business, Business)
    @application_data = T.let(application.application_data || {}, T::Hash[String, T.untyped])
  end

  sig { returns(T.nilable(String)) }
  def screen
    check_business_eligibility ||
      check_duplicate_payment_method ||
      check_crunchbase_link ||
      check_domain_email_alignment ||
      check_abuse_rate_limit
  end

  sig { returns(BusinessStartupsProgram) }
  attr_reader :application

  sig { returns(Business) }
  attr_reader :business

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :application_data

  sig { returns(T.nilable(String)) }
  def check_business_eligibility
    reasons = BusinessStartupsProgram::Application.business_ineligibility_reasons(business)
    reasons = reasons.reject { |r| r == "existing application" }
    return if reasons.empty?

    if reasons.include?("volume account")
      "not_metered"
    elsif reasons.include?("too old")
      "ineligible_enterprise_age"
    elsif reasons.include?("no payment method")
      "no_payment_method"
    else
      "ineligible_enterprise"
    end
  end

  sig { returns(T.nilable(String)) }
  def check_duplicate_payment_method
    card_fingerprint = application.payment_card_fingerprint
    azure_sub_id = application.payment_azure_subscription_id

    return if card_fingerprint.blank? && azure_sub_id.blank?

    scope = BusinessStartupsProgram
      .where.not(id: application.id)
      .where(application_status: :accepted)

    duplicate = if card_fingerprint.present? && azure_sub_id.present?
      scope.where(payment_card_fingerprint: card_fingerprint)
        .or(scope.where(payment_azure_subscription_id: azure_sub_id))
        .exists?
    elsif card_fingerprint.present?
      scope.where(payment_card_fingerprint: card_fingerprint).exists?
    else
      scope.where(payment_azure_subscription_id: azure_sub_id).exists?
    end

    return unless duplicate

    "duplicate_payment_method"
  end

  sig { returns(T.nilable(String)) }
  def check_crunchbase_link
    link = application_data["crunchbase_link"].to_s
    return if link.blank?
    return if BusinessStartupsProgram::Application.crunchbase_url?(link)

    REJECTION_MISSING_CRUNCHBASE
  end

  sig { returns(T.nilable(String)) }
  def check_domain_email_alignment
    email = application_data["email"].to_s
    website = application_data["company_website"].to_s

    return if email.blank? || website.blank?

    email_domain = extract_domain_from_email(email)
    website_domain = extract_domain_from_url(website)

    return if email_domain.blank? || website_domain.blank?
    return if domains_match?(email_domain, website_domain)

    REJECTION_DOMAIN_EMAIL_MISMATCH
  end

  sig { returns(T.nilable(String)) }
  def check_abuse_rate_limit
    keys_to_check = T.let([], T::Array[String])

    if application.payment_card_fingerprint.present?
      keys_to_check << "#{ABUSE_RATE_LIMIT_KEY_PREFIX}:card:#{application.payment_card_fingerprint}"
    end

    user_id = application_data["user_id"]
    if user_id.present?
      keys_to_check << "#{ABUSE_RATE_LIMIT_KEY_PREFIX}:user:#{user_id}"
    end

    keys_to_check.each do |key|
      limiter = RedisRateLimiter.new(key, max_tries: ABUSE_RATE_LIMIT_MAX, ttl: ABUSE_RATE_LIMIT_TTL)
      rate_result = limiter.rate
      return "suspected_abuse" if rate_result.at_limit?
    end

    nil
  end

  sig { params(email: String).returns(T.nilable(String)) }
  def extract_domain_from_email(email)
    parts = email.split("@")
    return if parts.length != 2

    parts.last&.downcase&.strip
  end

  sig { params(url: String).returns(T.nilable(String)) }
  def extract_domain_from_url(url)
    uri = URI.parse(url)
    host = uri.host || url.gsub(%r{https?://}, "").split("/").first
    host&.downcase&.strip&.sub(/\Awww\./, "")
  rescue URI::InvalidURIError
    nil
  end

  sig { params(email_domain: String, website_domain: String).returns(T::Boolean) }
  def domains_match?(email_domain, website_domain)
    return true if email_domain == website_domain
    return true if email_domain.end_with?(".#{website_domain}")
    return true if website_domain.end_with?(".#{email_domain}")

    false
  end
end
