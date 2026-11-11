# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Answers "was this feature recently enabled for this organization/business?"
  # Reads from the InProductTargeting domain's ipm_organization_matches and
  # ipm_enterprise_matches tables, which are written by the Copilot package
  # when CLI is toggled on.
  class FeatureEnablementAudit
    COPILOT_CLI_FEATURE = T.let(:copilot_cli, Symbol)
    SUPPORTED_FEATURES = T.let([COPILOT_CLI_FEATURE].freeze, T::Array[Symbol])
    CLI_ENABLED_COHORT = T.let("cli_enabled", String)

    sig do
      params(
        organization: Organization,
        feature: Symbol,
        within: ActiveSupport::Duration,
      ).returns(T::Boolean)
    end
    def self.feature_enabled_recently_for_organization?(organization:, feature:, within:)
      new(organization: organization).feature_enabled_recently?(feature: feature, within: within)
    end

    sig do
      params(
        business: Business,
        feature: Symbol,
        within: ActiveSupport::Duration,
      ).returns(T::Boolean)
    end
    def self.feature_enabled_recently_for_business?(business:, feature:, within:)
      new(business: business).feature_enabled_recently_for_business?(feature: feature, within: within)
    end

    sig { params(organization: T.nilable(Organization), business: T.nilable(Business)).void }
    def initialize(organization: nil, business: nil)
      raise ArgumentError, "organization or business is required" if organization.nil? && business.nil?

      @organization = T.let(organization, T.nilable(Organization))
      @business = T.let(business, T.nilable(Business))
    end

    sig { params(feature: Symbol, within: ActiveSupport::Duration).returns(T::Boolean) }
    def feature_enabled_recently?(feature:, within:)
      return false unless supported_runtime?
      return false unless SUPPORTED_FEATURES.include?(feature)
      return false unless feature_enabled_for_organization?(feature)

      cli_enabled_recently_for_org?(feature: feature, within: within)
    end

    sig { params(feature: Symbol, within: ActiveSupport::Duration).returns(T::Boolean) }
    def feature_enabled_recently_for_business?(feature:, within:)
      return false unless supported_runtime?
      return false unless SUPPORTED_FEATURES.include?(feature)
      return false unless feature_enabled_for_business?(feature)

      enterprise_match_exists_within?(enterprise_id: T.must(@business).id, within: within)
    end

    private

    sig { returns(T::Boolean) }
    def supported_runtime?
      return false if GitHub.enterprise?
      return false if GitHub.multi_tenant_enterprise?

      true
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def feature_enabled_for_organization?(feature)
      organization = @organization
      return false if organization.nil?

      case feature
      when COPILOT_CLI_FEATURE
        Copilot::Organization.new(organization).cli_enabled?
      else
        false
      end
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def policy_inherited_from_business?(feature)
      organization = @organization
      return false if organization.nil?

      case feature
      when COPILOT_CLI_FEATURE
        Copilot::Policies::Cli.org_policy_inherited?(Copilot::Organization.new(organization))
      else
        false
      end
    end

    sig { params(feature: Symbol).returns(T::Boolean) }
    def feature_enabled_for_business?(feature)
      business = @business
      return false if business.nil?

      case feature
      when COPILOT_CLI_FEATURE
        Copilot::Business.new(business).cli_enabled?
      else
        false
      end
    end

    # When the org inherits CLI policy from its business, check the business
    # matches; otherwise check the org's own matches.
    sig { params(feature: Symbol, within: ActiveSupport::Duration).returns(T::Boolean) }
    def cli_enabled_recently_for_org?(feature:, within:)
      organization = @organization
      return false if organization.nil?

      if policy_inherited_from_business?(feature)
        business = organization.business
        return false if business.nil?

        enterprise_match_exists_within?(enterprise_id: business.id, within: within)
      else
        org_match_exists_within?(organization_id: organization.id, within: within)
      end
    end

    # Checks whether a match exists on any calendar day within the lookback
    # window. This is day-granular: a match recorded on the boundary day will
    # be included even if the exact time is older than `within`.
    sig { params(organization_id: Integer, within: ActiveSupport::Duration).returns(T::Boolean) }
    def org_match_exists_within?(organization_id:, within:)
      start_day = within.ago.to_date.to_s

      matches = ::InProductTargeting.domain.matches_by_day(
        organization_id: organization_id,
        cohort: CLI_ENABLED_COHORT,
        start_day: start_day,
      )

      matches.any?
    end

    # Checks whether a match exists on any calendar day within the lookback
    # window. This is day-granular: a match recorded on the boundary day will
    # be included even if the exact time is older than `within`.
    sig { params(enterprise_id: Integer, within: ActiveSupport::Duration).returns(T::Boolean) }
    def enterprise_match_exists_within?(enterprise_id:, within:)
      start_day = within.ago.to_date.to_s

      matches = ::InProductTargeting.domain.matches_by_day(
        enterprise_id: enterprise_id,
        cohort: CLI_ENABLED_COHORT,
        start_day: start_day,
      )

      matches.any?
    end
  end
end
