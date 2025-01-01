# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class CodeScanningBusinessQuery < CodeScanningBaseQuery
        QUALIFIERS = (
          CodeScanningBaseQuery::QUALIFIERS + [
            (QUALIFIER_ORGANIZATION = :org),
            (QUALIFIER_REPOSITORY = :repo),
            (QUALIFIER_AUTOFIX = :autofix),
            (QUALIFIER_CAMPAIGN = :campaign),
          ]
        ).freeze

        class << self
          protected def allowed_qualifiers
            QUALIFIERS
          end
        end

        def is_valid?
          return false unless super
          return false unless has_any_valid_repo_nwo_values?
          return false unless has_valid_autofix?
          return false unless has_valid_campaign?
          return false unless has_valid_excluded_campaign?
          true
        end

        def autofix
          get_values_for_qualifier(QUALIFIER_AUTOFIX)
        end

        def autofix_enum
          autofix.map { |a| a.present? ? GitHub::Turboscan.to_autofix_filter(a) : nil }.compact
        end

        def has_valid_autofix?
          autofix.empty? || autofix_enum.present?
        end

        def excluded_autofix
          get_values_for_qualifier(negate_qualifier(QUALIFIER_AUTOFIX))
        end

        def excluded_autofix_enum
          excluded_autofix.map { |a| a.present? ? GitHub::Turboscan.to_autofix_filter(a) : nil }.compact
        end

        def has_valid_excluded_autofix?
          excluded_autofix.empty? || excluded_autofix_enum.present?
        end

        sig { returns(T::Array[String]) }
        def campaign
          get_values_for_qualifier(QUALIFIER_CAMPAIGN)
        end

        sig { returns(T::Array[Integer]) }
        def campaign_enum
          campaign.map { |c| c.present? ? GitHub::Turboscan.to_security_campaign_state(c) : nil }.compact
        end

        sig { returns(T::Boolean) }
        def has_valid_campaign?
          campaign.empty? || campaign_enum.present?
        end

        sig { returns(T::Array[String]) }
        def excluded_campaign
          get_values_for_qualifier(negate_qualifier(QUALIFIER_CAMPAIGN))
        end

        sig { returns(T::Array[Integer]) }
        def excluded_campaign_enum
          excluded_campaign.map { |c| c.present? ? GitHub::Turboscan.to_security_campaign_state(c) : nil }.compact
        end

        sig { returns(T::Boolean) }
        def has_valid_excluded_campaign?
          excluded_campaign.empty? || excluded_campaign_enum.present?
        end

        memoize def organization_names
          normalize_organization_names(get_values_for_qualifier(QUALIFIER_ORGANIZATION))
        end

        memoize def excluded_organization_names
          normalize_organization_names(get_values_for_qualifier(negate_qualifier(QUALIFIER_ORGANIZATION)))
        end

        def normalize_organization_names(unnormalized_organization_names)
          organization_names = unnormalized_organization_names
          # For all organization names, if they are not tenant-unique, include the tenant unique version too.
          organization_names += organization_names.filter_map { |name| User.standardize_login(name, suffix: GitHub::CurrentTenant.get.shortcode) unless User.unique_tenant_login?(name) }
        end

        def has_org?(org_name)
          organization_names.include?(org_name.downcase)
        end

        def repository_names
          @repository_names ||= get_values_for_qualifier(QUALIFIER_REPOSITORY)
        end

        def excluded_repository_names
          @excluded_repository_names ||= get_values_for_qualifier(negate_qualifier(QUALIFIER_REPOSITORY))
        end

        # Returns the NWOs specified in the query string in hash format: { org: ["repo", "repo2", ...], ... }.
        # Invalid NWOs are ignored.
        def repository_names_with_owner
          @nwos ||= build_nwo_hash(
            get_values_for_qualifier(QUALIFIER_REPOSITORY)
          )
        end

        # Returns the excluded NWOs specified in the query string in hash format: { org: ["repo", "repo2", ...], ... }.
        # Invalid NWOs are ignored.
        def excluded_repository_names_with_owner
          @excluded_nwos ||= build_nwo_hash(
            get_values_for_qualifier(negate_qualifier(QUALIFIER_REPOSITORY))
          )
        end

        def has_nwo?(nwo)
          parsed_nwo = build_nwo_hash([nwo])
          return false if parsed_nwo.empty?

          get_values_for_qualifier(QUALIFIER_REPOSITORY).include?(nwo)
        end

        private

        def build_nwo_hash(nwos)
          # NWOs must be in the form of "org/repo"
          nwos.reject! { |nwo| nwo.count("/") != 1 || nwo.start_with?("/") || nwo.end_with?("/") }

          # Split NWOs and convert to hash
          nwos.map { |nwo| nwo.split("/") }.each_with_object({}) do |pair, hsh|
            org_name = pair.first
            org_name = User.standardize_login(org_name, suffix: GitHub::CurrentTenant.get.shortcode) unless User.unique_tenant_login?(org_name)
            hsh[org_name] ||= []
            hsh[org_name] << pair.second
          end.with_indifferent_access
        end

        # Bad NWO values are ignored, so we pass this check if there are any valid NWOs in the provided values.
        def has_any_valid_repo_nwo_values?
          return true if get_values_for_qualifier(QUALIFIER_REPOSITORY).empty?
          repository_names_with_owner.any?
        end
      end
    end
  end
end
