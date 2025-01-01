# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class BusinessWarningHelper
    include GitHub::Memoizer

    ORGS_LIMIT = 200

    sig { params(owner: T.any(User, Organization, Business)).void }
    def initialize(owner)
      @owner = owner
      @memoized_banner_text = {}
    end

    sig { params(setting: Symbol, value: T.any(T::Boolean, String)).returns(T.nilable(String)) }
    def banner_text(setting:, value:)
      return nil unless @owner.is_a?(Business)

      key = "#{setting}_#{value}"
      return @memoized_banner_text[key] if @memoized_banner_text.key?(key)

      text = "This may override <a href='#{security_configs_docs_link}'>code security configurations</a> which have been applied at the organization level.".html_safe # rubocop:disable Rails/OutputSafety

      @memoized_banner_text[key] =
        if org_count > ORGS_LIMIT
          text
        elsif org_ids.empty?
          nil
        else
          query = SecurityConfiguration.where(target_type: "User", target_id: org_ids)
          case setting
          when :enable_ghas
            text if query.where.not(enable_ghas: value).exists?
          when :dependabot_alerts, :secret_scanning, :secret_scanning_push_protection, :secret_scanning_validity_checks, :secret_scanning_non_provider_patterns
            text if query.where.not({ "#{setting}" => [value, "not_set"] }).exists?
          else
            nil
          end
        end

      @memoized_banner_text[key]
    end

    def security_configs_docs_link
      "#{GitHub.help_url}/code-security/securing-your-organization/introduction-to-securing-your-organization-at-scale/about-enabling-security-features-at-scale"
    end

    memoize def org_count
      @owner.organizations.count
    end

    memoize def org_ids
      @owner.organizations.pluck(:id)
    end
  end
end
