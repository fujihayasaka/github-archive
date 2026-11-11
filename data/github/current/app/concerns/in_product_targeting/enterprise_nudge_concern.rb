# typed: true
# frozen_string_literal: true

module InProductTargeting
  module EnterpriseNudgeConcern
    extend ActiveSupport::Concern
    include HawaiiExperimentHelper
    include InProductTargeting::NudgeConcern

    NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

    sig { params(key: Symbol, business: T.nilable(Business)).returns(NudgeConfig) }
    def get_new_tasks_nudge_config(key, business = nil)
      case key
      when :sparkorcli
        NudgeConfig.new(
          nudge_type: :sparkorcli,
          nudge_id: :nudge_enterprise_preview_spark_and_cli,
          nudge_feature_flag: :nudge_enterprise_preview_spark_and_cli,
          nudge_group: :engage,
          destination_key: :nudge_enterprise_preview_spark_and_cli,
        )
      when :loops
        NudgeConfig.new(
          nudge_type: :loops,
          nudge_id: :nudge_enterprise_preview_loops,
          nudge_feature_flag: :nudge_enterprise_preview_loops,
          nudge_group: :engage,
          destination_key: :nudge_enterprise_preview_loops
        )
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
      nudge_keys = [:win_cb_users_back_credit, :loops, :sparkorcli]

      nudge_key_to_show = nudge_keys.find { |key| show_enterprise_tasks_nudge?(current_user, business, key) }
      return nil unless nudge_key_to_show

      get_new_tasks_nudge_config(nudge_key_to_show, business)
    end

    sig { params(current_user: User, business: Business, key: Symbol).returns(T::Boolean) }
    def show_enterprise_tasks_nudge?(current_user, business, key)
      nudge_config = get_new_tasks_nudge_config(key, business)

      return false unless passes_user_segmentation?(current_user, business)
      return false if current_user.dismissed_business_notice?(nudge_config.nudge_id.to_s, business_id: business.id)
      nudge_feature_flag = nudge_config.nudge_feature_flag
      return false unless nudge_feature_flag.nil? || current_user.feature_flag_enabled?(nudge_feature_flag, default: false)

      case key
      when :sparkorcli
        eligible_for_sparkorcli_nudge?(current_user, business)
      when :loops
        eligible_for_loops_nudge?(current_user, business)
      when :win_cb_users_back_credit
        eligible_for_win_cb_users_back_credit_nudge?(current_user, business)
      else
        false
      end
    end

    sig { params(user: User, business: Business).returns(T::Boolean) }
    def passes_user_segmentation?(user, business)
      return false unless user.subscribed_to_in_product_messages?
      return false if is_business_in_active_dfd_trial?(business)
      return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || user.is_enterprise_managed?

      true
    end

    sig { params(current_user: User, business: Business).returns(T::Boolean) }
    def eligible_for_sparkorcli_nudge?(current_user, business)
      return false unless business.owner?(current_user)
      return false unless business.created_at < 31.days.ago
      return false if business.trial_expired? || business.trial_cancelled?

      business_copilot = Copilot::Business.new(business)
      return false if business_copilot.copilot_disabled_for_all_organizations?
      return false if business_copilot.copilot_disabled?
      return false unless business_copilot.cli_disabled? || business_copilot.spark_disabled?

      true
    end

    sig { params(current_user: User, business: Business).returns(T::Boolean) }
    def eligible_for_loops_nudge?(current_user, business)
      return false unless business.owner?(current_user)
      return false unless business.created_at < 31.days.ago
      return false if business.trial_expired? || business.trial_cancelled?

      business_copilot = Copilot::Business.new(business)
      return false if business_copilot.copilot_disabled_for_all_organizations?
      return false if business_copilot.copilot_disabled?
      return false unless Copilot::Policies::Loops.unconfigured?(business_copilot) || Copilot::Policies::Loops.disabled?(business_copilot)

      true
    end

    sig { params(current_user: User, business: Business).returns(T::Boolean) }
    def eligible_for_win_cb_users_back_credit_nudge?(current_user, business)
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
  end
end
