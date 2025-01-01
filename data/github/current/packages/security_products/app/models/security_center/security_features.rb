# typed: strict
# frozen_string_literal: true

module SecurityCenter
  class SecurityFeatures
    extend T::Sig

    # REPOSITORY_CONFIGURATION is a special type of feature, not stored in repository_security_center_status table
    # We are adding it so we can reuse the jobs (update and reconciliation), but then
    # we branch inside these jobs to execute a different kind of data ingestion and update.
    REPOSITORY_CONFIGURATION = "repository_configuration"
    SECRET_SCANNING = "secret_scanning"
    CODE_SCANNING = "code_scanning"
    DEPENDABOT_ALERTS = "dependabot_alerts"

    EMU_READY_FEATURES = T.let([SECRET_SCANNING], T::Array[String])

    FEATURE_TYPES_BY_VIEW_PERMISSION = T.let({
      view_secret_scanning_alerts: SECRET_SCANNING,
      read_code_scanning: CODE_SCANNING,
      view_dependabot_alerts: DEPENDABOT_ALERTS
    }, T::Hash[Symbol, String])

    VIEW_PERMISSIONS_BY_FEATURE_TYPE = T.let({
      SECRET_SCANNING => :view_secret_scanning_alerts,
      CODE_SCANNING => :read_code_scanning,
      DEPENDABOT_ALERTS => :view_dependabot_alerts
    }, T::Hash[String, Symbol])

    # All data categories that we consume in security center
    #   For example: feature types such as "secret_scanning", and configuration types
    sig { returns(T::Array[String]) }
    def self.all
      RepositorySecurityCenterStatus.primary_feature_types.map(&:to_s).push(REPOSITORY_CONFIGURATION)
    end

    # A subset of data categories that we consume in security center
    # This list only includes enabled categories for the environment setup (dotcom vs GHES)
    #   For example: in GHES, Secret Scanning requires enablement at the GHE Config level
    #   in order to show up in the product.
    sig { params(target: T.nilable(T.any(Business, Organization, User))).returns(T::Array[String]) }
    def self.all_visible(target)
      self.visible_features(target).push(REPOSITORY_CONFIGURATION)
    end

    # Is the full security center experience available/enabled for the specified target?
    sig { params(target: T.nilable(T.any(Business, Organization, User))).returns(T::Boolean) }
    def self.full_security_center_available?(target)
      target&.advanced_security_purchased?
    end

    # On dotcom, a "limited" version of Security Overview is available to businesses/orgs with the "business_plus" plan who
    # have not paid for GHAS.
    #
    # On GHES, a "limited" version of Security Overview is available if the business has not paid for GHAS.
    #
    # @param target [Organization, Business]
    # @param dotcom_request_only [boolean] Ensure the instance is a dotcom environment.
    # @return [boolean]
    sig do
      params(target: T.nilable(T.any(Business, Organization, User)), dotcom_request_only: T::Boolean)
      .returns(T::Boolean)
    end
    def self.limited_security_center_available?(target, dotcom_request_only: false)
      return false if target.nil?

      # Relax org/biz check to conditionally allow enterprise owned accounts
      entity = target
      if target.is_a?(User) && target.user? && target.is_enterprise_managed?
        return false unless ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(target)

        entity = target.enterprise_managed_business
      end

      return false unless entity.plan.business_plus? || GitHub.enterprise?
      return false if GitHub.enterprise? && dotcom_request_only

      # After above checks, we know we're in a case where a user will either have full security center
      # or limited security center. Check that they don't have full security center.
      !full_security_center_available?(target)
    end

    # Is security center, either the full or the limited experience, available/enabled for the specified target?
    #
    # @param dotcom_request_only [boolean] Ensure the instance is a dotcom environment.
    # @return [boolean]
    sig do
      params(target: T.nilable(T.any(Business, Organization, User)), dotcom_request_only: T::Boolean)
      .returns(T::Boolean)
    end
    def self.security_center_available?(target, dotcom_request_only: false)
      full_security_center_available?(target) || limited_security_center_available?(target, dotcom_request_only: dotcom_request_only)
    end

    sig { params(target: T.nilable(T.any(Business, Organization, User))).returns(T::Array[String]) }
    def self.visible_features(target)
      instance_enabled_features = []
      RepositorySecurityCenterStatus.primary_feature_types.each do |feature_type|
        case feature_type
        when :code_scanning
          instance_enabled_features << CODE_SCANNING if self.code_scanning_enabled_for_instance?
        when :secret_scanning
          instance_enabled_features << SECRET_SCANNING if self.secret_scanning_enabled_for_instance?
        when :dependabot_alerts
          instance_enabled_features << DEPENDABOT_ALERTS if self.dependabot_alerts_enabled_for_instance?
        end
      end

      return instance_enabled_features if target.nil?

      is_user_target = target.is_a?(User) && target.user?
      show_emu_ready_features = is_user_target && ::SecurityCenter::FeatureFlagHelper.allows_emu_owned_repositories?(target)

      # None emu owner is unexpected and should have access to no visible features.
      if is_user_target && !show_emu_ready_features
        GitHub.dogstats.increment("security_center.visible_features.non_emu_target")
        GitHub.logger.info(
          "Unexpected call to visible_features by non emu target",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.user.id": target.id,
        )
        # Prior to EMU work, we ignored user as if the target were nil which was simply because an user target wasn't possible and unexpected.
        # While I'm sure all places calling this function now should either be an org/business or an EMU, will validate the telemetry prior to
        # feature flag removal.
        return ::SecurityCenter::FeatureFlagHelper.no_visible_features_for_non_emu_owners?(target) ? [] : instance_enabled_features
      end

      available_features = if target.advanced_security_purchased?
        instance_enabled_features
      else
        # From here, we can assume that the target is:
        # * Either an org or a business
        # * EMU, otherwise, requires GHAS

        # Dependabot Alerts are always visible regardless of plan/GHES state
        visible_features = [DEPENDABOT_ALERTS]

        # Limited security center is by definition when GHAS is _not_ purchased
        # which we already check above and return.
        # This call ends up just checking that billable entity has a business_plus license
        # and that it's not in GHES
        if limited_security_center_available?(target, dotcom_request_only: true)
          visible_features += [SECRET_SCANNING, CODE_SCANNING]
        end

        instance_enabled_features & visible_features
      end

      return available_features & EMU_READY_FEATURES if show_emu_ready_features

      available_features
    end

    sig { returns(T::Boolean) }
    def self.code_scanning_enabled_for_instance?
      GitHub.code_scanning_enabled?
    end

    sig { returns(T::Boolean) }
    def self.secret_scanning_enabled_for_instance?
      SecurityProduct::TokenScanning.enabled_for_instance?
    end

    sig { returns(T::Boolean) }
    def self.dependabot_alerts_enabled_for_instance?
      SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
    end
  end
end
