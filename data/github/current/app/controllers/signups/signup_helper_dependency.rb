# typed: true
# frozen_string_literal: true

module Signups
  module SignupHelperDependency
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    included do
      # Global helpers for general use
      T.bind(self, T.class_of(ApplicationController))
      helper_method :device_and_ip_updates
      helper_method :conditional_free_copilot_license
      helper_method :signup_tasks_and_data_collection
    end

    sig { params(user: User).returns(T.nilable(AuthenticatedDevice)) }
    def device_and_ip_updates(user)
      current_device = if user.sign_in_analysis_enabled?
        # approve devices on new accounts by default
        user.authenticated_devices.create!(
          accessed_at: Time.now,
          approved_at: Time.now,
          device_id: current_device_id,
          display_name: AuthenticatedDevice.generated_display_name(parsed_useragent),
        )
      end

      GlobalInstrumenter.instrument "user.signup.ip_update", {
        actor: user,
        signup_email: user.emails.first,
        actor_ip: user.most_recent_session&.ip,
        actor_location: user.most_recent_session&.location,
      }

      current_device
    end

    def conditional_free_copilot_license(user)
      # TODO: if removing :social_early_license, please replace with GitHub.social_sisu_enabled? check once social has shipped
      return unless user.feature_flag_enabled_or_raise?(:social_early_license) && (vscode_return_to) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      # optimistically provision free license if the user is coming from VSCode and has been shown the legal warning
      copilot_user = Copilot::User.new(user)
      restrictor = Copilot::Authorization::TradeRestrictor.new(copilot_user)
      if GitHub.context.present? && restrictor.restricted?(GitHub.context, {})
        return GitHub.logger.info("trade restricted", "code.namespace": "SignupsController", "code.function": "verify_email_and_register_social_identity", "gh.request_id": request_id)
      end

      result = copilot_user.subscribe_limited_user(skip_copilot_signup_email: true)
      return Copilot::Instrumenter.instrument_signup_limited_subscription_created(copilot_user,
        utm_query_params: {
          utm_medium: "social_signup",
        }) if result.ok?

      GitHub.logger.info(result.error.message, "code.namespace": "SignupsController", "code.function": "verify_email_and_register_social_identity", "gh.request_id": request_id)
    end

    def signup_tasks_and_data_collection(user, email, country_code, marketing_consent)
      user.queue_signup_tasks
      user.accept_tos

      if country_code.present? && !marketing_consent.nil?
        UserSignup.capture_user_signup_data(
          user: user,
          email: email,
          country_code: country_code,
          gave_explicit_marketing_consent: marketing_consent
        )
        if FeatureFlag.vexi.enabled?(:user_marketing_consent_table, default: false)
          UserMarketingConsent.capture_user_signup_data(
            user_id: user.id,
            email: email,
            country_code: country_code,
            gave_explicit_marketing_consent: marketing_consent
          )
        end
      end
    end
  end
end
