# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module EnterpriseNudgeConcern
    extend ActiveSupport::Concern
    include BusinessesHelper
    include InProductTargeting::NudgeConcern

    NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

    ENTERPRISE_PREVIEW_NUDGE_KEYS = T.let(
      [:copilot_cli_enablement, :win_cb_users_back_credit, :copilot_coding_agent_enablement].freeze,
      T::Array[Symbol]
    )
    ENTERPRISE_ORGANIZATIONS_NUDGE_KEYS = T.let(
      [:copilot_coding_agent_enablement].freeze,
      T::Array[Symbol]
    )
    DEFAULT_FEATURE_ENABLEMENT_WINDOW = T.let(14.days, ActiveSupport::Duration)

    sig { params(key: Symbol, business: T.nilable(Business)).returns(NudgeConfig) }
    def get_new_tasks_nudge_config(key, business = nil)
      case key
      when :win_cb_users_back_credit
        # Fetch the expires date from metadata if business is provided
        expires_date = nil
        if business
          match = find_in_product_targeting_enterprise_cohort_data(
            enterprise_id: business.id,
            cohort: :nov_2025_copilot_digital_offer_for_enterprises.to_s
          )
          expires_date = match["expires"] if match && match["expires"].present?
        end

        NudgeConfig.new(
          nudge_type: :win_cb_users_back_credit,
          nudge_id: :nudge_enterprise_win_cb_users_back_credit,
          nudge_feature_flag: :nudge_enterprise_win_cb_users_back_credit,
          nudge_group: :engage,
          destination_key: :nudge_enterprise_win_cb_users_back_credit,
          expires: expires_date
        )
      when :copilot_cli_enablement
        NudgeConfig.new(
          nudge_type: :copilot_cli_enablement,
          nudge_id: :ipm_copilot_cli_enterprise_nudge,
          nudge_feature_flag: :ipm_copilot_cli_ga_enterprise_nudge,
          nudge_group: :engage,
          destination_key: :ipm_copilot_cli_enterprise_nudge
        )
      when :copilot_coding_agent_enablement
        NudgeConfig.new(
          nudge_type: :copilot_coding_agent_enablement,
          nudge_id: :copilot_coding_agent_enterprise_nudge,
          nudge_feature_flag: :copilot_coding_agent_enterprise_nudge,
          nudge_group: :engage,
          destination_key: :copilot_coding_agent_enterprise_nudge
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

    sig { params(current_user: User, business: Business).returns(T.nilable(NudgeConfig)) }
    def nudge_to_show(current_user, business)
      # First perform cheap segmentation gating to avoid unnecessary work for
      # ineligible users (e.g., unsubscribed to IPM/EMU, non-enterprise).
      return nil unless passes_user_segmentation?(current_user, business)

      # Check show_ai_controls? once upfront to avoid redundant Twirp RPCs to
      # BillingPlatform. Without this, each eligible_for_* method independently
      # calls show_ai_controls?, triggering a ~40ms RPC per nudge key per business.
      # With 4 nudge keys × 5 businesses, that's ~20 RPCs (~1.8s) eliminated.
      return nil unless show_ai_controls?(business)

      ENTERPRISE_PREVIEW_NUDGE_KEYS.each do |key|
        config = get_new_tasks_nudge_config(key, business)
        return config if show_enterprise_tasks_nudge?(current_user, business, key, config)
      end
      nil
    end

    sig { params(key: Symbol).returns(NudgeConfig) }
    def get_dashboard_nudge_config(key)
      case key
      when :dashboard_copilot_cli_enabled
        NudgeConfig.new(
          nudge_type: :ipm_accelerate_dashboard_business_copilot_cli_enabled,
          nudge_id: :ipm_accelerate_dashboard_business_copilot_cli_enabled_nudge,
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

    # This is a common gatekeeping method for all of the enterprise preview nudges. If there is a need for a new enterprise preview nudge, add a new method for eligibility and add a new case in this method that calls the eligibility method.
    sig { params(current_user: User, business: Business, key: Symbol, nudge_config: T.nilable(NudgeConfig)).returns(T::Boolean) }
    def show_enterprise_dashboard_nudge?(current_user, business, key, nudge_config = nil)
      nudge_config ||= get_dashboard_nudge_config(key)

      return false unless passes_user_segmentation?(current_user, business)
      return false if current_user.dismissed_business_notice?(nudge_config.nudge_id.to_s, business_id: business.id)
      nudge_feature_flag = nudge_config.nudge_feature_flag
      return false unless nudge_feature_flag.nil? || current_user.feature_flag_enabled?(nudge_feature_flag, default: false)

      case key
      when :dashboard_copilot_cli_enabled
        eligible_for_dashboard_copilot_cli_enabled_nudge?(current_user, business)
      else
        false
      end
    end

    # This is a common gatekeeping method to determine if a specific nudge is able to be rendered.
    sig { params(current_user: User, business: Business, key: Symbol, nudge_config: T.nilable(NudgeConfig)).returns(T::Boolean) }
    def show_enterprise_tasks_nudge?(current_user, business, key, nudge_config = nil)
      nudge_config ||= get_new_tasks_nudge_config(key, business)

      return false unless passes_user_segmentation?(current_user, business)
      return false if current_user.dismissed_business_notice?(nudge_config.nudge_id.to_s, business_id: business.id)
      nudge_feature_flag = nudge_config.nudge_feature_flag
      return false unless nudge_feature_flag.nil? || current_user.feature_flag_enabled?(nudge_feature_flag, default: false)

      case key
      when :win_cb_users_back_credit
        eligible_for_win_cb_users_back_credit_nudge?(current_user, business)
      when :copilot_cli_enablement
        eligible_for_copilot_cli_nudge?(current_user, business)
      when :copilot_coding_agent_enablement
        return false unless current_user.feature_flag_enabled?(:copilot_enterprise_nudge_enterprises, default: false)
        eligible_for_copilot_coding_agent_nudge?(current_user, business)
      else
        false
      end
    end

    # This is the shared gatekeeping logic for all of the renderable nudges. If a common conditional statement is needed it belongs here.
    sig { params(user: User, business: Business).returns(T::Boolean) }
    def passes_user_segmentation?(user, business)
      return false unless user.subscribed_to_in_product_messages?
      return false if is_business_in_active_dfd_trial?(business)
      return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || user.is_enterprise_managed?
      return false unless ::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", business_id: business.id)

      true
    end

    sig { params(current_user: User, business: Business).returns(T::Boolean) }
    def eligible_for_win_cb_users_back_credit_nudge?(current_user, business)
      return false unless show_ai_controls?(business)
      return false unless business.owner?(current_user)
      return false if business.trial_expired? || business.trial_cancelled?

      # Don't show the nudge if the user has opted out of in-product messaging. A requirement from privacy for this nudge
      return false unless current_user.subscribed_to_in_product_messages?

      # Check if business is in the list of enterprises coming from Twirp, which
      # was a manually run query that retrieved all businesses that were a CB customer prior to 2025, but aren't CB customers today
      match = find_in_product_targeting_enterprise_cohort_data(
        enterprise_id: business.id,
        cohort: :nov_2025_copilot_digital_offer_for_enterprises.to_s
      )
      return false unless match

      # Check if the nudge has expired
      if match["expires"].present?
        begin
          expiration_date = Date.parse(match["expires"])
          return false if Time.now.utc.to_date >= expiration_date
        rescue ArgumentError
          # Invalid date format in metadata, log and continue
          GitHub.logger.warn("Invalid expiration date in metadata", {
            "in_product_targeting.expires" => match["expires"],
            "in_product_targeting.cohort" => :nov_2025_copilot_digital_offer_for_enterprises.to_s,
            "in_product_targeting.enterprise_id" => business.id
          })
        end
      end

      business_copilot = Copilot::Business.new(business)

      # Three states for showing the nudge:
      # 1. Copilot is disabled -> show nudge with "Enable Copilot Business" CTA
      # 2. Copilot is enabled (all/some orgs) AND (0 seats assigned OR 0 organizations granted access) -> show nudge with "Grant access" CTA
      # 3. Copilot is enabled (all/some orgs) AND 1+ seats AND 1+ organizations granted access -> don't show nudge
      if business_copilot.copilot_enabled?
        # If copilot is enabled, only show nudge if there are 0 seats assigned OR 0 organizations granted access
        return business_copilot.copilot_seat_count == 0 || business_copilot.copilot_accessible_organization_count == 0
      end

      # Show nudge if copilot is disabled
      true
    end


    sig { params(current_user: User, business: Business).returns(T::Boolean) }
    def eligible_for_copilot_cli_nudge?(current_user, business)
      return false unless show_ai_controls?(business)
      return false unless business.owner?(current_user)
      return false if business.trial_expired? || business.trial_cancelled?

      business_copilot = Copilot::Business.new(business)
      return false if business_copilot.copilot_disabled_for_all_organizations?
      return false if business_copilot.copilot_disabled?
      return false if business_copilot.cli_enabled?
      return false if business_copilot.cli_no_policy? # Let orgs decide

      true
    end

    sig { params(current_user: User, business: Business).returns(T::Boolean) }
    def eligible_for_copilot_coding_agent_nudge?(current_user, business)
      return false unless show_ai_controls?(business)
      return false unless business.owner?(current_user)
      return false if business.trial_expired? || business.trial_cancelled?

      business_copilot = Copilot::Business.new(business)
      return false if business_copilot.copilot_disabled_for_all_organizations?
      return false if business_copilot.copilot_disabled?
      return false if business_copilot.swe_agent_enabled?
      return false if business_copilot.swe_agent_no_policy? # Let orgs decide

      true
    end

    sig { params(current_user: User, business: Business).returns(T::Boolean) }
    def eligible_for_dashboard_copilot_cli_enabled_nudge?(current_user, business)
      return false unless show_ai_controls?(business)
      return false if business.owner?(current_user)
      return false if business.trial_expired? || business.trial_cancelled?
      return false unless user_has_copilot_seat_for_business?(current_user, business)

      business_copilot = Copilot::Business.new(business)
      return false if business_copilot.copilot_disabled_for_all_organizations?
      return false if business_copilot.copilot_disabled?
      return false unless business_copilot.cli_enabled?
      return false if business_copilot.cli_no_policy? # Let orgs decide

      InProductTargeting::FeatureEnablementAudit.feature_enabled_recently_for_business?(
        business: business,
        feature: :copilot_cli,
        within: DEFAULT_FEATURE_ENABLEMENT_WINDOW,
      )
    end

    sig { params(user: User, business: Business).returns(T::Boolean) }
    def user_has_copilot_seat_for_business?(user, business)
      Copilot::Seat
        .joins(:seat_assignment)
        .where(assigned_user_id: user.id)
        .where(copilot_seat_assignments: { owner_type: "Organization", owner_id: business.organization_ids, access_revoked_at: nil })
        .exists?
    end

    sig { params(user: User, business: Business, page_feature_flag: Symbol, cta_href: String, dismiss_path: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def build_coding_agent_nudge_props(user, business, page_feature_flag:, cta_href:, dismiss_path:)
      return nil unless user.feature_flag_enabled?(:copilot_coding_agent_enterprise_nudge, default: false)
      return nil unless user.feature_flag_enabled?(page_feature_flag, default: false)
      return nil unless passes_user_segmentation?(user, business)

      nudge_config = get_new_tasks_nudge_config(:copilot_coding_agent_enablement, business)
      return nil if user.dismissed_business_notice?(nudge_config.nudge_id.to_s, business_id: business.id)
      return nil unless eligible_for_copilot_coding_agent_nudge?(user, business)

      {
        ctaHref: cta_href,
        dismissPath: dismiss_path,
        businessId: business.id,
      }
    end
  end
end
