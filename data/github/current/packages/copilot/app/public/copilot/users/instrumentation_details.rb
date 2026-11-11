# typed: strict
# frozen_string_literal: true

module Copilot
  module Users
    module InstrumentationDetails
      extend T::Helpers
      include Copilot::Users::Signatures
      include Copilot::Instrumentation::ModelDetails

      abstract!

      sig { override.params(include_trust_tier: T::Boolean).returns(CopilotUserDetails) }
      def copilot_user_details(include_trust_tier: false)
        {
          copilot_user_settings: copilot_user_settings,
          subscription_plan: copilot_subscription_plan,
          is_trial: copilot_active_subscription_item.present? ? T.must(copilot_active_subscription_item).on_free_trial? : false,
          is_technical_preview_user: is_technical_preview_user?,
          free_access_type: copilot_free_user_type,
          trust_tier: include_trust_tier ? trust_tier : nil,
        }
      end

      sig { override.returns(T::Hash[Symbol, Symbol]) }
      def copilot_user_settings
        # merge in special cases for policies that don't have a specific class
        # mostly here for backwards compatibility
        Copilot::Policies.instrumentation_hash(T.bind(self, Copilot::User)).merge({
          telemetry_configuration: copilot_telemetry_configuration,
          overages_setting: copilot_overages_setting,
          insights_setting: :INSIGHTS_UNCONFIGURED, # will never be set for users
        })
      end

      sig { override.returns(Symbol) }
      def copilot_telemetry_configuration
        return :ENABLED if telemetry_enabled?
        :DISABLED
      end

      sig { override.returns(Symbol) }
      def copilot_overages_setting
        return :OVERAGES_UNCONFIGURED unless overages_configured?
        return :OVERAGES_ENABLED if overages_enabled?
        return :OVERAGES_DISABLED if overages_disabled?

        :OVERAGES_UNKNOWN
      end

      sig { override.returns(Symbol) }
      def copilot_subscription_plan
        return :NO_SUBSCRIPTION unless copilot_active_subscription_item.present?
        return :MONTHLY if T.must(copilot_active_subscription_item).monthly?
        return :YEARLY if T.must(copilot_active_subscription_item).yearly?

        :UNKNOWN_PLAN
      end

      sig { override.returns(Symbol) }
      def copilot_free_user_type
        free_user = FreeUser.find_by(user: self)
        return :FREE_USER_NOT_PRESENT unless free_user.present?

        case free_user.type
        when Copilot::FreeUser::GITHUB_STAR
          :GITHUB_STAR
        when Copilot::FreeUser::MS_MVP
          :MS_MVP
        when Copilot::FreeUser::WORKSHOP
          :WORKSHOP
        when Copilot::FreeUser::Y_COMBINATOR
          :Y_COMBINATOR
        when Copilot::FreeUser::ENGAGED_OSS
          :ENGAGED_OSS
        when Copilot::FreeUser::EDUCATIONAL
          :EDUCATIONAL
        when Copilot::FreeUser::FACULTY
          :FACULTY
        when Copilot::FreeUser::COMPLIMENTARY_ACCESS
          :COMPLIMENTARY_ACCESS
        when Copilot::FreeUser::TECHNICAL_PREVIEW_EXTENSION
          :TECHNICAL_PREVIEW_EXTENSION
        when Copilot::FreeUser::HEY_GITHUB
          :HEY_GITHUB
        else
          # we should never hit here?
          :FREE_USER_UNKNOWN
        end
      end

      sig { returns(Symbol) }
      def trust_tier
        tier = TrustTiers::Tier.for_billable_owner(self.user_object).tier

        # If the user is a seat holder, we need to check the trust tier of the billing plan owner(s)
        if self.access_type.to_s.include?("SEAT")
          copilot_seats = Copilot::Seat.includes(:seat_assignment).where(assigned_user_id: self.user_object.id)
          ff_check = self.user_object.feature_flag_enabled_or_raise?(:copilot_bpo_trust_tier_nil_check) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          copilot_seats.each do |seat|
            if ff_check && (seat.nil? || seat.seat_assignment.nil? || seat.seat_assignment.owner.nil?)
              # If the seat assignment or owner is nil, we can't determine trust tier
              GitHub.logger.info(
                "Nil seat assignment for user",
                "code.namespace" => "Copilot::Users::InstrumentationDetails",
                "code.function" => Kernel.__method__,
                "gh.user.id" => self.user_object.id,
                "copilot.access_type" => self.access_type,
              )
              next
            end
            current_trust_tier = TrustTiers::Tier.for_billable_owner(seat.seat_assignment.owner).tier
            tier = current_trust_tier if current_trust_tier < tier
          end
        end

        return :TRUST_TIER_UNTRUSTED if tier == TrustTiers::Tier::UNTRUSTED
        return :TRUST_TIER_NEUTRAL if tier == TrustTiers::Tier::NEUTRAL
        return :TRUST_TIER_TRUSTED if tier == TrustTiers::Tier::TRUSTED

        :TRUST_TIER_UNKNOWN
      end
    end
  end
end
