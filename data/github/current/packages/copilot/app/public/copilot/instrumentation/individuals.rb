# typed: strict
# frozen_string_literal: true

module Copilot
  module Instrumentation
    module Individuals
      include Helpers

      sig { params(user: ::User, blocking_reason: String, integration_id: T.nilable(String)).void }
      def instrument_user_abuse_event(user, blocking_reason, integration_id = nil)
        instrument(::Copilot::Events::USER_ABUSE_EVENT, {
          user: user,
          integration_id: integration_id,
          blocking_reason: blocking_reason,
        })
      end

      # this is when a staff user or automation removes copilot access for a user
      sig { params(copilot_user: Copilot::User, staff_actor: ::User, block_reason: String, access_type: T.nilable(Symbol)).void }
      def instrument_administrative_block(copilot_user, staff_actor, block_reason, access_type: nil)
        access_type ||= copilot_user.access_type
        instrument(::Copilot::Events::ADMINISTRATIVE_BLOCK, {
          staff_actor: staff_actor,
          user: copilot_user.user_object,
          block_reason: block_reason,
          access_type: access_type,
          state: Copilot::AdministrativeBlock::ACTIVE_STATE,
        })
      end

      # this is when a staff user warns a user for copilot abuse
      sig { params(copilot_user: Copilot::User, staff_actor: ::User, block_reason: String, access_type: T.nilable(Symbol)).void }
      def instrument_administrative_warn(copilot_user, staff_actor, block_reason, access_type: nil)
        access_type ||= copilot_user.access_type
        instrument(::Copilot::Events::ADMINISTRATIVE_WARN, {
          staff_actor: staff_actor,
          user: copilot_user.user_object,
          block_reason: block_reason,
          access_type: access_type,
          state: Copilot::AdministrativeBlock::WARNED_STATE,
        })
      end

      # this is when a staff user warns a user for copilot abuse
      sig { params(user: ::User, staff_actor: ::User, feature: String, previous_quota: Integer, new_quota: Integer).void }
      def instrument_free_quota_changed_by_staff(user, staff_actor, feature, previous_quota, new_quota)

        instrument(::Copilot::Events::FREE_QUOTA_CHANGED_BY_STAFF, {
          staff_actor: staff_actor,
          user: user,
          feature: feature,
          previous_quota: previous_quota,
          new_quota: new_quota,
        })
      end

      # this is when a staff user unsubscribes a copilot free user
      sig { params(user: ::User, staff_actor: ::User).void }
      def instrument_free_user_unsubscribed_by_staff(user, staff_actor)
        instrument(::Copilot::Events::FREE_UNSUBSCRIBED_BY_STAFF, {
          staff_actor: staff_actor,
          user: user,
        })
      end

      sig { params(user: ::User).void }
      def instrument_show_copilot(user)
        instrument(::Copilot::Events::SHOW_COPILOT, {
          user: user,
        })
      end

      sig { params(user: ::User).void }
      def instrument_hide_copilot(user)
        instrument(::Copilot::Events::HIDE_COPILOT, {
          user: user,
        })
      end

      # this is when a staff user returns copilot access to a user
      sig { params(user: ::User, staff_actor: ::User, block_reason: String).void }
      def instrument_administrative_unblock(user, staff_actor, block_reason)
        instrument(::Copilot::Events::ADMINISTRATIVE_UNBLOCK, {
          staff_actor: staff_actor,
          user: user,
          block_reason: block_reason,
          state: Copilot::AdministrativeBlock::REVOKED_STATE,
        })
      end

      # this is when a staff user grants free access to a user
      sig { params(user: ::User, staff_actor: ::User, free_user_type: String, complimentary_access_duration: Date, complimentary_access_reason_explanation: String).void }
      def instrument_free_access_granted(user, staff_actor, free_user_type, complimentary_access_duration, complimentary_access_reason_explanation)
        instrument(::Copilot::Events::COMPLIMENTARY_ACCESS_GRANTED, {
          staff_actor: staff_actor,
          user: user,
          complimentary_access_duration: complimentary_access_duration.to_date.to_s,
          complimentary_access_reason_explanation: complimentary_access_reason_explanation,
          free_user_type: free_user_type,
        })
      end

      # this is when a staff user removes free access from a user
      sig { params(user: ::User, staff_actor: ::User, free_user_type: String, remove_access_reason_explanation: String).void }
      def instrument_free_access_removed(user, staff_actor, free_user_type, remove_access_reason_explanation)
        instrument(::Copilot::Events::COMPLIMENTARY_ACCESS_REMOVED, {
          staff_actor: staff_actor,
          user: user,
          remove_access_reason_explanation: remove_access_reason_explanation,
          free_user_type: free_user_type,
        })
      end

      # This is when a user has acknowledge the notification sent to them.
      sig { params(copilot_user: Copilot::User, notification_id: String).void }
      def instrument_editor_notification_acknowledged(copilot_user, notification_id)
        instrument(::Copilot::Events::EDITOR_NOTIFICATION, {
          copilot_user: copilot_user,
          notification_event_type: :ACKNOWLEDGED,
          notification_event_name: notification_id,
        })
      end

      # This is when a user has been shown a notification.
      sig { params(copilot_user: Copilot::User, notification_id: String, headers: T::Hash[Symbol, String]).void }
      def instrument_editor_notification_shown(copilot_user, notification_id, headers)
        instrument(::Copilot::Events::EDITOR_NOTIFICATION, {
          copilot_user: copilot_user,
          notification_event_type: :SHOWN,
          notification_event_name: notification_id,
          editor_version: headers[:editor_version],
          editor_plugin_version: headers[:editor_plugin_version],
        })
      end

      # This is when the free user has been cancelled in the background job
      sig { params(copilot_user: Copilot::User).void }
      def instrument_free_user_cancelled(copilot_user)
        instrument(::Copilot::Events::FREE_USER_EVENT, {
          copilot_user: copilot_user,
          free_user_event_type: :CANCELLED,
        })
      end

      # This is when the free user has been refreshed in the background job
      sig { params(copilot_user: Copilot::User).void }
      def instrument_free_user_refreshed(copilot_user)
        instrument(::Copilot::Events::FREE_USER_EVENT, {
          copilot_user: copilot_user,
          free_user_event_type: :REFRESHED,
        })
      end

      # This is when a free user has been warned that their access is about to
      # expire.
      sig { params(copilot_user: Copilot::User).void }
      def instrument_free_user_warned(copilot_user)
        instrument(::Copilot::Events::FREE_USER_EVENT, {
          copilot_user: copilot_user,
          free_user_event_type: :WARNED,
        })
      end

      # This is when the user changes their copilot settings in the setting controller
      sig do
        params(
          copilot_user: Copilot::User,
          old_settings: T::Hash[Symbol, Symbol],
          new_settings: T::Hash[Symbol, Symbol],
        ).void
      end
      def instrument_settings_saved(copilot_user, old_settings: {}, new_settings: {})
        instrument(::Copilot::Events::SETTINGS_SAVED, {
          copilot_user: copilot_user,
          old_settings: old_settings,
          new_settings: new_settings,
        })
      end

      sig do
        params(
          copilot_user: Copilot::User,
          utm_query_params: T::Hash[Symbol, String],
        ).void
      end
      def instrument_signup_confirmed_payment(copilot_user, utm_query_params: {})
        instrument(::Copilot::Events::SIGNUP_CONFIRMED_PAYMENT, {
          copilot_user: copilot_user,
        }.merge(utm_parameters(utm_query_params)))
      end

      sig do
        params(
          copilot_user: T.any(Copilot::User, Copilot::Public::User),
          utm_query_params: T::Hash[Symbol, String],
        ).void
      end
      def instrument_signup_free_page_view(copilot_user, utm_query_params: {})
        instrument(::Copilot::Events::SIGNUP_FREE_PAGE_VIEW, {
          copilot_user: copilot_user,
        }.merge(utm_parameters(utm_query_params)))
      end

      sig do
        params(
          copilot_user: Copilot::User,
          utm_query_params: T::Hash[Symbol, String],
        ).void
      end
      def instrument_signup_free_subscription_created(copilot_user, utm_query_params: {})
        instrument(::Copilot::Events::SIGNUP_FREE_SUBSCRIPTION_CREATED, {
          copilot_user: copilot_user,
        }.merge(utm_parameters(utm_query_params)))
      end

      sig do
        params(
          copilot_user: Copilot::User,
          utm_query_params: T::Hash[Symbol, String],
        ).void
      end
      def instrument_signup_limited_subscription_created(copilot_user, utm_query_params: {})
        instrument(::Copilot::Events::LIMITED_USER_SUBSCRIBED, {
          copilot_user: copilot_user,
        }.merge(utm_parameters(utm_query_params)))
      end

      sig do
        params(
          copilot_user: T.nilable(T.any(Copilot::User, Copilot::Public::User)),
          utm_query_params: T::Hash[Symbol, String],
        ).void
      end
      def instrument_signup_page_view(copilot_user, utm_query_params: {})
        instrument(::Copilot::Events::SIGNUP_PAGE_VIEW, {
          copilot_user: copilot_user,
        }.merge(utm_parameters(utm_query_params)))

        variation =
          case
          when copilot_user&.user_object&.has_commercial_interaction_restriction?
            "commercial_interaction_restriction"
          when copilot_user&.eligible_for_trial?
            "standard"
          when !copilot_user
            "logged_out"
          else
            "renewal"
          end

        GitHub.dogstats.increment "copilot.signup-page-view", tags: [
          "variation:#{variation}",
          "subscription_ended:#{copilot_user&.has_subscription_ended? || false}",
          "technical_preview_user:#{copilot_user&.is_technical_preview_user? || false}",
          "technical_preview_user_lost_access:#{copilot_user&.technical_preview_user_lost_access? || false}",
        ]
      end

      sig do
        params(
          copilot_user: Copilot::User,
          plan_name: String,
          utm_query_params: T::Hash[Symbol, String],
        ).void
      end
      def instrument_signup_plan_chosen(copilot_user, plan_name, utm_query_params: {})
        instrument(::Copilot::Events::SIGNUP_PLAN_CHOSEN, {
          copilot_user: copilot_user,
          chosen_plan: plan_name,
        }.merge(utm_parameters(utm_query_params)))
      end

      sig do
        params(
          copilot_user: T.any(Copilot::User, Copilot::Public::User),
          utm_query_params: T::Hash[Symbol, String],
        ).void
      end
      def instrument_signup_saved_address(copilot_user, utm_query_params: {})
        instrument(::Copilot::Events::SIGNUP_SAVED_ADDRESS, {
          copilot_user: copilot_user,
        }.merge(utm_parameters(utm_query_params)))
      end

      sig do
        params(
          copilot_user: Copilot::User,
          old_settings: T::Hash[Symbol, Symbol],
          new_settings: T::Hash[Symbol, Symbol],
          utm_query_params: T::Hash[Symbol, String],
        ).void
      end
      def instrument_signup_settings_saved(copilot_user, old_settings: {}, new_settings: {}, utm_query_params: {})
        instrument(::Copilot::Events::SIGNUP_SETTINGS_SAVED, {
          copilot_user: copilot_user,
          old_settings: old_settings,
          new_settings: new_settings,
        }.merge(utm_parameters(utm_query_params)))
      end

      sig do
        params(
          copilot_user: Copilot::User,
          plan_name: String,
          trial_length: Integer,
          utm_query_params: T::Hash[Symbol, String],
        ).void
      end
      def instrument_signup_subscription_created(copilot_user, plan_name, trial_length, utm_query_params: {})
        instrument(::Copilot::Events::SIGNUP_SUBSCRIPTION_CREATED, {
          copilot_user: copilot_user,
          copilot_subscription_plan: plan_name,
          trial_length: trial_length,
        }.merge(utm_parameters(utm_query_params)))
      end

      sig do
        params(
          copilot_user: Copilot::User,
          subscription_plan: String,
          in_trial: T::Boolean,
        ).void
      end
      def instrument_subscription_cancelled(copilot_user, subscription_plan, in_trial: false)
        instrument(::Copilot::Events::SUBSCRIPTION_CANCELLED, {
          copilot_user: copilot_user,
          subscription_plan: subscription_plan,
          in_trial: in_trial,
        })
      end

      # # TODO: This requires changes to billing to support - Commenting out for now
      # sig { params(copilot_user: Copilot::User, in_trial: T::Boolean, old_duration: Integer, new_duration: Integer).void }
      # def instrument_subscription_duration_changed(copilot_user, in_trial, old_duration, new_duration)
      #   instrument(::Copilot::Events::SUBSCRIPTION_DURATION_CHANGED, {
      #     copilot_user: copilot_user,
      #     in_trial: in_trial,
      #     old_subscription_plan: old_duration,
      #     new_subscription_plan: new_duration,
      #   })
      # end

      sig do
        params(
          copilot_user: Copilot::User,
          failure_reason: String,
          headers: T::Hash[Symbol, String],
        ).void
      end
      def instrument_token_failed(copilot_user, failure_reason, headers)
        instrument(::Copilot::Events::TOKEN_FAILURE, {
          copilot_user: copilot_user,
          failure_reason: failure_reason,
          editor_version: headers[:editor_version],
          editor_plugin_version: headers[:editor_plugin_version],
        })

        dd_tags = ["failure_reason:#{failure_reason}"]
        GitHub.dogstats.increment("copilot.token.failure", tags: dd_tags)
      end

      sig do
        params(
          copilot_user: Copilot::User,
          token_expiration: Integer,
          access_type: Symbol,
          headers: T::Hash[Symbol, String],
          organization_list: T::Array[String],
          source: String,
        ).void
      end
      def instrument_token_generated(copilot_user, token_expiration, access_type, headers, organization_list, source: "token_generation")
        # calling send_to_hydro skips sending to the audit log
        send_to_hydro(
          ::Copilot::Events::TOKEN_GENERATED,
          {
            copilot_user: copilot_user,
            copilot_access_type: access_type,
            expires_at: token_expiration,
            editor_version: headers[:editor_version],
            editor_plugin_version: headers[:editor_plugin_version],
            free_enterprise_organization_name: nil,
            organization_list: organization_list,
            source: source,
          },
        )
        dd_tags = ["access_type:#{access_type}", "source:#{source}"]
        GitHub.dogstats.increment("copilot.token.success", tags: dd_tags)
      end

      sig do
        params(
          actor: ::User,
          country_code: T.nilable(String),
          region: T.nilable(String),
          region_name: T.nilable(String),
          city: T.nilable(String),
        ).void
      end
      def instrument_trade_restricted_country_block(actor, country_code, region, region_name, city)
        instrument(::Copilot::Events::TRADE_RESTRICTED_COUNTRY_BLOCK, {
          actor: actor,
          current_ip: GitHub.context[:actor_ip],
          current_location: {
            country_code: country_code,
            region: region,
            region_name: region_name,
            city: city,
          },
        })
      end

      sig do
        params(
          copilot_user: Copilot::User,
          subscription_plan: String,
        ).void
      end
      def instrument_trial_subscription_converts(copilot_user, subscription_plan)
        instrument(::Copilot::Events::TRIAL_SUBSCRIPTION_CONVERTS, {
          copilot_user: copilot_user,
          subscription_plan: subscription_plan,
        })
      end
    end
  end
end
