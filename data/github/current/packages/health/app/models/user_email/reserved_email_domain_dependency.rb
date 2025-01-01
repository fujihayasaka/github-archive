# typed: true
# frozen_string_literal: true

module UserEmail::ReservedEmailDomainDependency
  RESERVED_EMAIL_DOMAINS = [
    "toyota.com",
    "lexus.com"
  ]

  RESERVED_DOMAIN_REGEX = Regexp.new(/@(#{RESERVED_EMAIL_DOMAINS.map { |d| Regexp.escape(d) }.join('|')})\z/i)

  RESERVED_DOMAIN_NEW_EMAIL_MESSAGE = %q(The email address you are trying to add is controlled by Toyota Motor North America.
    Please reach out to ApplicationSecurity@toyota.com)

  RESERVED_DOMAIN_NEW_ACCOUNT_MESSAGE = %q(The email address you are trying to create an account with is controlled by Toyota Motor North America.
    Please reach out to ApplicationSecurity@toyota.com.)

  def self.is_reserved_domain?(email)
    return false unless !GitHub.single_business_environment?

    email.present? && RESERVED_DOMAIN_REGEX.match?(email)
  end
end
