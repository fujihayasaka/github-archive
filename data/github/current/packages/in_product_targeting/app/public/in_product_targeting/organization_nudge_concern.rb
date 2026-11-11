# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module OrganizationNudgeConcern
    extend ActiveSupport::Concern
    include InProductTargeting::NudgeConcern

    NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

    DEFAULT_FEATURE_ENABLEMENT_WINDOW = T.let(14.days, ActiveSupport::Duration)

    sig { params(user: User, organization: Organization, key: Symbol).returns(T::Boolean) }
    def show_organization_tasks_nudge?(user, organization, key)
      case key
      when :raf_cb
        return false unless passes_user_segmentation_for_raf_cb_nudge?(
          user,
          organization,
        )

        eligible_for_raf_cb_nudge?(user, organization)
      when :win_cb_users_back_credit_offer_to_accept
        return false unless passes_user_segmentation_for_win_cb_users_back_credit_offer_to_accept_nudge?(
          user,
          organization,
        )

        eligible_for_win_cb_users_back_credit_offer_to_accept_nudge?(user, organization)
      when :win_cb_users_back_credit
        return false unless passes_user_segmentation_for_win_cb_users_back_credit_nudge?(
          user,
          organization,
        )

        eligible_for_win_cb_users_back_credit_nudge?(user, organization)
      when :win_cb_users_back_credit_assign_seats
        return false unless passes_user_segmentation_for_win_cb_users_back_credit_nudge?(
          user,
          organization,
        )

        eligible_for_win_cb_users_back_credit_assign_seats_nudge?(user, organization)
      when :copilot_cli_enablement
        return false unless passes_user_segmentation_for_copilot_cli_nudge?(user, organization)

        eligible_for_copilot_cli_nudge?(user, organization)
      else
        false
      end
    end

    sig { params(user: User, organization: Organization).returns(T.nilable(NudgeConfig)) }
    def nudge_to_show_settings_page(user, organization)
      nudge_keys = [
        :win_cb_users_back_credit_offer_to_accept,
        :win_cb_users_back_credit_assign_seats,
        :win_cb_users_back_credit,
        :copilot_cli_enablement,
        :raf_cb,
      ]

      nudge_key_to_show = nudge_keys.find { |key| show_organization_tasks_nudge?(user, organization, key) }
      return nil unless nudge_key_to_show

      get_new_tasks_nudge_config(nudge_key_to_show, organization)
    end

    sig { params(key: Symbol, organization: T.nilable(Organization)).returns(NudgeConfig) }
    def get_new_tasks_nudge_config(key, organization = nil)
      case key
      when :raf_cb
        NudgeConfig.new(
          nudge_type: :raf_cb,
          nudge_id: :organization_new_tasks_raf_cb_nudge,
          nudge_feature_flag: :organization_new_tasks_raf_cb_nudge,
          nudge_group: :engage,
          destination_key: :cb_settings_organizations_new_tasks_raf
        )
      when :win_cb_users_back_credit_offer_to_accept
        # Fetch the expires date from metadata if organization is provided
        expires_date = nil
        if organization
          match = find_in_product_targeting_organization_cohort_data(
            organization_id: organization.id,
            cohort: :nov_2025_copilot_digital_offer_to_accept_for_organizations.to_s
          )
          expires_date = match["expires"] if match && match["expires"].present?
        end

        NudgeConfig.new(
          nudge_type: :win_cb_users_back_credit_offer_to_accept,
          nudge_id: :nudge_organization_win_cb_users_back_credit_offer_to_accept,
          nudge_feature_flag: :nudge_organization_win_cb_users_back_credit_offer_to_accept,
          nudge_group: :engage,
          destination_key: :nudge_organization_win_cb_users_back_credit_offer_to_accept,
          expires: expires_date
        )
      when :win_cb_users_back_credit
        expires_date = fetch_expires_date_for_organization(
          organization,
          :nov_2025_copilot_digital_offer_for_organizations.to_s
        )

        NudgeConfig.new(
          nudge_type: :win_cb_users_back_credit,
          nudge_id: :nudge_organization_win_cb_users_back_credit,
          nudge_feature_flag: :nudge_organization_win_cb_users_back_credit,
          nudge_group: :engage,
          destination_key: :nudge_organization_win_cb_users_back_credit,
          expires: expires_date
        )
      when :win_cb_users_back_credit_assign_seats
        expires_date = fetch_expires_date_for_organization(
          organization,
          :nov_2025_copilot_digital_offer_for_organizations.to_s
        )

        NudgeConfig.new(
          nudge_type: :win_cb_users_back_credit_assign_seats,
          nudge_id: :nudge_organization_win_cb_users_back_credit,
          nudge_feature_flag: :nudge_organization_win_cb_users_back_credit,
          nudge_group: :engage,
          destination_key: :nudge_organization_win_cb_users_back_credit_assign_seats,
          expires: expires_date
        )
      when :copilot_cli_enablement
        NudgeConfig.new(
          nudge_type: :copilot_cli_enablement,
          nudge_id: :ipm_copilot_cli_organization_nudge,
          nudge_feature_flag: :ipm_copilot_cli_ga_organization_nudge,
          nudge_group: :engage,
          destination_key: :ipm_copilot_cli_organization_nudge
        )
      else
        NudgeConfig.new(
          nudge_type: :unknown,
          nudge_id: :unknown,
          nudge_feature_flag: :unknown,
          nudge_group: :unknown,
          destination_key: :unknown
        )
      end
    end

    # Universal segmentation checks that apply to all organization nudges.
    # Returns false if the user/organization should not see any nudges.
    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def passes_universal_user_segmentation?(user, organization)
      return false unless user.feature_flag_enabled?(:organization_new_tasks_nudges, default: false)
      return false unless user.subscribed_to_in_product_messages?
      return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || user.is_enterprise_managed?
      return false unless organization.adminable_by?(user)
      return false if organization.plan == GitHub::Plan.business_plus && organization.business&.owner?(user)
      return false unless ::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", organization_id: organization.id)
      business = organization.business
      return false if business && !::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", business_id: business.id)

      true
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def passes_user_segmentation_for_win_cb_users_back_credit_nudge?(user, organization)
      nudge_config = get_new_tasks_nudge_config(:win_cb_users_back_credit)

      return false unless passes_universal_user_segmentation?(user, organization)

      return false if user.businesses.any? { |business| is_business_in_active_dfd_trial?(business) }

      nudge_feature_flag = nudge_config.nudge_feature_flag
      return false unless nudge_feature_flag.nil? || user.feature_flag_enabled?(nudge_feature_flag, default: false)

      return false if user.dismissed_organization_notice?(nudge_config.nudge_id.to_s, organization)

      true
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def passes_user_segmentation_for_win_cb_users_back_credit_offer_to_accept_nudge?(user, organization)
      nudge_config = get_new_tasks_nudge_config(:win_cb_users_back_credit_offer_to_accept)

      return false unless passes_universal_user_segmentation?(user, organization)

      return false if user.businesses.any? { |business| is_business_in_active_dfd_trial?(business) }

      nudge_feature_flag = nudge_config.nudge_feature_flag
      return false unless nudge_feature_flag.nil? || user.feature_flag_enabled?(nudge_feature_flag, default: false)

      return false if user.dismissed_organization_notice?(nudge_config.nudge_id.to_s, organization)

      true
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def passes_user_segmentation_for_raf_cb_nudge?(user, organization)
      nudge_config = get_new_tasks_nudge_config(:raf_cb)

      return false unless passes_universal_user_segmentation?(user, organization)

      return false if user.businesses.any? { |business| is_business_in_active_dfd_trial?(business) }
      return false if organization.business&.sales_managed?

      nudge_feature_flag = nudge_config.nudge_feature_flag
      return false unless nudge_feature_flag.nil? || user.feature_flag_enabled?(nudge_feature_flag, default: false)

      # for :organization_new_tasks_raf_cb_nudge, if the organization:
      #   - has Copilot enabled: then we don't give them the ability to dismiss the Nudge -- the OrgAdmin can either accept or dismiss RAF requests to hide the nudge
      #   - does not have Copilot enabled: we allow the OrgAdmin to dismiss the nudge; they will only ever see the nudge once until they enable Copilot for the Org,
      #     at which point they will see the nudges normally in the above case
      if nudge_config.nudge_id == :organization_new_tasks_raf_cb_nudge
        return false if
          !Copilot::Organization.new(organization).has_copilot_for_business? &&
          user.dismissed_organization_notice?(nudge_config.nudge_id.to_s, organization)
      end

      true
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def eligible_for_raf_cb_nudge?(user, organization)
      return false if organization.plan == GitHub::Plan.business_plus

      # check the current_users's monitoring settings; only show nudges for feature requests they care about
      # i.e. don't show any nudges if the WatchButton is in "Ignore" mode
      #      if WatchButton is in custom mode, only show nudge if "copilot business" is checked
      monitoring_settings = Notifications::Settings.member_feature_requests(user, organization.id)

      # if we failed to load the monitoring_settings, then treat it as if we had requested monitoring for CB
      if !monitoring_settings || monitoring_settings.features.include?(MemberFeatureRequest::Feature::CopilotForBusiness)
        users_requesting_features = MemberFeatureRequest.total_by_feature(organization)
        num_users_requesting_cb = users_requesting_features[MemberFeatureRequest::Feature::CopilotForBusiness] || 0
        return num_users_requesting_cb > 0
      end

      false
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def eligible_for_win_cb_users_back_credit_offer_to_accept_nudge?(user, organization)
      return false if organization.plan == GitHub::Plan.business_plus

      # Check if organization is in the list of organizations coming from Twirp, which
      # was a manually run query that retrieved all organizations that were a CB customer prior to 2025, but aren't CB customers today
      match = find_in_product_targeting_organization_cohort_data(
        organization_id: organization.id,
        cohort: :nov_2025_copilot_digital_offer_to_accept_for_organizations.to_s
      )
      return false unless match

      # Check if the nudge has expired
      if match["expires"].present?
        begin
          expiration_date = Date.parse(match["expires"])
          return false if Time.now.utc.to_date > expiration_date
        rescue ArgumentError
          # Invalid date format in metadata, log and continue
          GitHub.logger.warn("Invalid expiration date in metadata", {
            "in_product_targeting.expires" => match["expires"],
            "in_product_targeting.cohort" => :nov_2025_copilot_digital_offer_to_accept_for_organizations.to_s,
            "in_product_targeting.organization_id" => organization.id
          })
        end
      end

      org_copilot = Copilot::Organization.new(organization)
      return false if org_copilot.has_copilot_for_business?

      true
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def eligible_for_win_cb_users_back_credit_nudge?(user, organization)
      return false if organization.plan == GitHub::Plan.business_plus

      # Make sure the user has accepted the offer first
      return false unless user.dismissed_organization_notice?("nudge_organization_win_cb_users_back_credit_offer_to_accept", organization)
      # Check if organization is in the list of organizations coming from Twirp, which
      # was a manually run query that retrieved all organizations that were a CB customer prior to 2025, but aren't CB customers today
      match = find_in_product_targeting_organization_cohort_data(
        organization_id: organization.id,
        cohort: :nov_2025_copilot_digital_offer_for_organizations.to_s
      )
      return false unless match

      cohort = :nov_2025_copilot_digital_offer_for_organizations.to_s
      return false unless check_expiration_date(
        match: match,
        cohort: cohort,
        organization_id: organization.id
      )

      org_copilot = Copilot::Organization.new(organization)
      return false if org_copilot.has_copilot_for_business?

      true
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def eligible_for_win_cb_users_back_credit_assign_seats_nudge?(user, organization)
      return false if organization.plan == GitHub::Plan.business_plus

      # Make sure the user has accepted the offer first
      return false unless user.dismissed_organization_notice?("nudge_organization_win_cb_users_back_credit_offer_to_accept", organization)
      # Check if organization is in the list of organizations coming from Twirp, which
      # was a manually run query that retrieved all organizations that were a CB customer prior to 2025, but aren't CB customers today
      match = find_in_product_targeting_organization_cohort_data(
        organization_id: organization.id,
        cohort: :nov_2025_copilot_digital_offer_for_organizations.to_s
      )
      return false unless match

      cohort = :nov_2025_copilot_digital_offer_for_organizations.to_s
      return false unless check_expiration_date(
        match: match,
        cohort: cohort,
        organization_id: organization.id
      )

      org_copilot = Copilot::Organization.new(organization)
      return false unless org_copilot.has_copilot_for_business?
      return false if org_copilot.has_copilot_for_business? && org_copilot.has_assigned_seats?

      true
    end


    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def passes_user_segmentation_for_copilot_cli_nudge?(user, organization)
      nudge_config = get_new_tasks_nudge_config(:copilot_cli_enablement)

      return false unless passes_universal_user_segmentation?(user, organization)

      nudge_feature_flag = nudge_config.nudge_feature_flag
      return false unless nudge_feature_flag.nil? || user.feature_flag_enabled?(nudge_feature_flag, default: false)
      return false if user.dismissed_organization_notice?(nudge_config.nudge_id.to_s, organization)

      true
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def eligible_for_copilot_cli_nudge?(user, organization)
      return false if organization.plan == GitHub::Plan.business_plus

      org_copilot = Copilot::Organization.new(organization)
      return false unless org_copilot.has_copilot_for_business?
      return false if org_copilot.cli_enabled?

      true
    end

    sig { params(key: Symbol).returns(NudgeConfig) }
    def get_dashboard_nudge_config(key)
      case key
      when :dashboard_copilot_cli_enabled
        NudgeConfig.new(
          nudge_type: :ipm_accelerate_dashboard_copilot_cli_enabled,
          nudge_id: :ipm_accelerate_dashboard_copilot_cli_enabled_nudge,
          nudge_feature_flag: :ipm_accelerate_dashboard_copilot_cli_enabled_nudge,
          nudge_group: :engage,
          destination_key: :ipm_accelerate_dashboard_copilot_cli_enabled_nudge
        )
      else
        NudgeConfig.new(
          nudge_type: :unknown,
          nudge_id: :unknown,
          nudge_feature_flag: :unknown,
          nudge_group: :unknown,
          destination_key: :unknown
        )
      end
    end

    sig { params(current_user: User, organization: Organization, key: Symbol, nudge_config: T.nilable(NudgeConfig)).returns(T::Boolean) }
    def show_organization_dashboard_nudge?(current_user, organization, key, nudge_config = nil)
      nudge_config ||= get_dashboard_nudge_config(key)

      nudge_feature_flag = nudge_config.nudge_feature_flag
      return false unless nudge_feature_flag.nil? || current_user.feature_flag_enabled?(nudge_feature_flag, default: false)
      return false if current_user.dismissed_organization_notice?(nudge_config.nudge_id.to_s, organization)

      case key
      when :dashboard_copilot_cli_enabled
        eligible_for_dashboard_copilot_cli_enabled_nudge?(current_user, organization)
      else
        false
      end
    end

    sig { params(current_user: User, organization: Organization).returns(T::Boolean) }
    def eligible_for_dashboard_copilot_cli_enabled_nudge?(current_user, organization)
      return false if organization.adminable_by?(current_user)
      # Enterprise-linked orgs (business_plus) get the business-level nudge via
      # EnterpriseNudgeConcern instead; skip them here to avoid duplicates.
      return false if organization.plan.business_plus?
      return false unless Copilot::Organization.new(organization).cli_enabled?
      return false unless user_has_copilot_seat_for?(current_user, organization)

      InProductTargeting::FeatureEnablementAudit.feature_enabled_recently_for_organization?(
        organization: organization,
        feature: :copilot_cli,
        within: DEFAULT_FEATURE_ENABLEMENT_WINDOW,
      )
    end

    sig { params(user: User, organization: Organization).returns(T::Boolean) }
    def user_has_copilot_seat_for?(user, organization)
      Copilot::Seat.for_assigned_user_and_owner(user, organization)
        .where(copilot_seat_assignments: { access_revoked_at: nil })
        .exists?
    end

    private

    sig { params(organization: T.nilable(Organization), cohort: String).returns(T.nilable(String)) }
    def fetch_expires_date_for_organization(organization, cohort)
      return nil unless organization

      match = find_in_product_targeting_organization_cohort_data(
        organization_id: organization.id,
        cohort: cohort
      )
      return nil unless match

      expires_value = match["expires"]
      expires_value.present? ? expires_value : nil
    end

    sig { params(match: T::Hash[String, T.untyped], cohort: String, organization_id: Integer).returns(T::Boolean) }
    def check_expiration_date(match:, cohort:, organization_id:)
      expires_value = match["expires"]
      return true unless expires_value.present?

      begin
        expiration_date = Date.parse(expires_value)
        return false if Time.now.utc.to_date >= expiration_date
      rescue ArgumentError
        GitHub.logger.warn("Invalid expiration date in metadata", {
          "in_product_targeting.expires" => expires_value,
          "in_product_targeting.cohort" => cohort,
          "in_product_targeting.organization_id" => organization_id
        })
      end

      true
    end
  end
end
