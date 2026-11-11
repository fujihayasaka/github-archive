# typed: true
# frozen_string_literal: true

module UserEmail::ReservedEmailDomainDependency
  # Structured configuration for all reserved email domain groups.
  # Each group has its own domains, messages, redirect URL, and optional feature flag.
  # To add a new group: add an entry here and run the boot-time validation to verify.
  RESERVED_DOMAIN_CONFIGS = {
    toyota: {
      domains: %w[toyota.com lexus.com],
      org_name: "Toyota",
      flag: nil,
      redirect_url: "https://github.toyota.com",
      contact_email: "ApplicationSecurity@toyota.com",
      contexts: {
        new_account: "The email address you are trying to create an account with is controlled by Toyota Motor North America. Please reach out to ApplicationSecurity@toyota.com.",
        new_email: "The email address you are trying to add is controlled by Toyota Motor North America. Please reach out to ApplicationSecurity@toyota.com",
      },
    },
    deloitte_nexus: {
      domains: %w[deloitte.com deloitte.il],
      org_name: "Deloitte",
      flag: :reserved_domains_deloitte,
      redirect_url: "https://nexus.deloitte.com/",
      contact_email: "ushostingecr@deloitte.com",
      contexts: {
        new_account: "Your email domain is managed by Deloitte. Visit nexus.deloitte.com or contact ushostingecr@deloitte.com.",
        new_email: "This email domain is managed by Deloitte. Visit nexus.deloitte.com or contact ushostingecr@deloitte.com.",
      },
    },
    deloitte_global: {
      domains: %w[
        deloitte.co.uk deloitte.com.au deloitte.it deloittece.com deloitte.ca
        deloitte.es tohmatsu.co.jp deloitte.de deloitte.pt deloitte.nl
        deloitte.gr deloitte.fr deloitte.ie deloitte.dk deloitte.co.za
        deloitte.lu deloitte.co.nz deloitte.com.tw deloitte.com.cn deloitte.ch
        deloitte.fi deloitte.no deloitte.se deloitte.at deloitte.com.hk
        deloitte.is deloittemx.com deloitte.kz deloitte.com.ng deloitte.co.ke
        contractor.deloitte.es deloitte.tn deloitte.ua deloitte.com.na
        s2g.deloitte.es externosdeloittemx.com avocats.deloitte.fr
        deloitte.com.gh deloitte.co.jp deloitte.co.zm deloitte.ge kbvl.gr
        deloitte.co.tz deloitte.uz deloitte.com.mt deloittedigital.es
        sts.deloitte.it
      ],
      org_name: "Deloitte",
      flag: :reserved_domains_deloitte,
      redirect_url: "https://www.deloittegithub.com/",
      contact_email: "dtenterprisecoderepositoryteam@deloitte.com",
      contexts: {
        new_account: "Your email domain is managed by Deloitte. Visit deloittegithub.com or contact dtenterprisecoderepositoryteam@deloitte.com.",
        new_email: "This email domain is managed by Deloitte. Visit deloittegithub.com or contact dtenterprisecoderepositoryteam@deloitte.com.",
      },
    },
    xpi: {
      domains: %w[xpi.com.br],
      org_name: "XP Investimentos",
      flag: :reserved_domains_xpi,
      redirect_url: "https://github.com/xpinc",
      contact_email: "si.appsec@xpi.com.br",
      contexts: {
        new_account: "The email address you are trying to create an account with is controlled by XP Inc. Please reach out to si.appsec@xpi.com.br.",
        new_email: "The email address you are trying to add is controlled by XP Inc. Please reach out to si.appsec@xpi.com.br.",
      },
    },
  }.freeze

  # O(1) reverse lookup: domain string → { group_key:, config: }
  domain_to_group = RESERVED_DOMAIN_CONFIGS.each_with_object({}) do |(group_key, config), hash|
    config[:domains].each { |d| hash[d] = { group_key: group_key, config: config } }
  end
  DOMAIN_TO_GROUP = domain_to_group.freeze

  # Generic fallback for consumers that read from static constants (e.g., sessions_controller)
  FALLBACK_MESSAGE = "This email domain is reserved. Please contact your organization's administrator."

  # Deprecated constants — preserved for backward compatibility with consumers not yet
  # migrated to the new config API. Remove after all consumers use config_for_email.
  RESERVED_EMAIL_DOMAINS = RESERVED_DOMAIN_CONFIGS.values.flat_map { |c| c[:domains] }.freeze
  RESERVED_DOMAIN_NEW_EMAIL_MESSAGE = RESERVED_DOMAIN_CONFIGS[:toyota][:contexts][:new_email]
  RESERVED_DOMAIN_NEW_ACCOUNT_MESSAGE = RESERVED_DOMAIN_CONFIGS[:toyota][:contexts][:new_account]

  def self.domain_from_email(email)
    str = email.to_s
    return nil unless str.include?("@")
    str.split("@").last&.downcase&.strip
  end

  def self.config_for_email(email)
    domain = domain_from_email(email)
    DOMAIN_TO_GROUP.dig(domain, :config)
  end

  def self.group_key_for_email(email)
    domain = domain_from_email(email)
    DOMAIN_TO_GROUP.dig(domain, :group_key)
  end

  def self.message_for_email(email, context:)
    config = config_for_email(email)
    message_for_config(config, context: context)
  end

  def self.message_for_config(config, context:)
    return nil unless config
    config.dig(:contexts, context)
  end

  def self.is_reserved_domain?(email)
    return false if GitHub.single_business_environment?

    config_for_email(email).present?
  end

  # Safe extraction helper for consumers reading from ActiveModel errors.
  # Returns the group-specific message if present, otherwise a generic fallback.
  def self.extract_reserved_error_message(errors)
    error = errors.where(:email, :reserved_domain).first
    error&.options&.dig(:message) || FALLBACK_MESSAGE
  end

  # Validates the RESERVED_DOMAIN_CONFIGS structure.
  # Called from tests to catch duplicate domains, invalid formats, and missing context messages.
  def self.validate_domain_configs!
    seen = {}
    RESERVED_DOMAIN_CONFIGS.each do |group_key, config|
      config[:domains].each do |domain|
        raise "Duplicate domain #{domain} in #{group_key} and #{seen[domain]}" if seen[domain]
        raise "Invalid domain format: #{domain}" unless domain.match?(/\A[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}\z/)
        seen[domain] = group_key
      end
      %i[new_account new_email].each do |ctx|
        raise "Missing context #{ctx} for #{group_key}" unless config.dig(:contexts, ctx).present?
      end
    end
  end
end
