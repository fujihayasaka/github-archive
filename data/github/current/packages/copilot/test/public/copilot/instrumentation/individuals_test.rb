# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Instrumentation::IndividualsTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @product_uuid_subscribable ||= create(:billing_product_uuid, :copilot)
    @yearly_product_uuid_subscribable = create(:billing_product_uuid, :copilot, billing_cycle: :year)
  end

  context "administrative_warn" do
    test "audits and publishes to hydro" do
      user = create(:user)
      staff = create(:staff_admin_user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::ADMINISTRATIVE_WARN

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_administrative_warn(
          copilot_user,
          staff,
          "reasons",
        )
      end

      assert_subset_hash(
        {
          staff_actor_id: staff.id,
          user_id: user.id,
          action: event,
        },
        events.first,
      )

      assert_hydro_published(
        {
          staff_actor: Hydro::EntitySerializer.user(staff),
          user: Hydro::EntitySerializer.user(user),
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          block_reason: "reasons",
          state: Copilot::AdministrativeBlock::WARNED_STATE,
          copilot_access_type: :UNKNOWN,
        },
        schema: "github.copilot.v2.CopilotUserAdministrativeBlock"
      )
    end
  end

  context "administrative_unblock" do
    test "audits and publishes to hydro" do
      user = create(:user)
      staff = create(:staff_admin_user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::ADMINISTRATIVE_UNBLOCK

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_administrative_unblock(
          user,
          staff,
          "reasons",
        )
      end

      assert_subset_hash(
        {
          staff_actor_id: staff.id,
          user_id: user.id,
          action: event,
        },
        events.first,
      )

      assert_hydro_published(
        {
          staff_actor: Hydro::EntitySerializer.user(staff),
          user: Hydro::EntitySerializer.user(user),
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          block_reason: "UNBLOCKED - reasons",
          state: Copilot::AdministrativeBlock::REVOKED_STATE,
        },
        schema: "github.copilot.v2.CopilotUserAdministrativeBlock"
      )
    end
  end

  context "administrative_block" do
    test "audits and publishes to hydro" do
      user = create(:user)
      staff = create(:staff_admin_user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::ADMINISTRATIVE_BLOCK

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_administrative_block(
          copilot_user,
          staff,
          "reasons",
        )
      end

      assert_subset_hash(
        {
          staff_actor_id: staff.id,
          user_id: user.id,
          action: event,
        },
        events.first,
      )

      assert_hydro_published(
        {
          staff_actor: Hydro::EntitySerializer.user(staff),
          user: Hydro::EntitySerializer.user(user),
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          block_reason: "reasons",
          state: Copilot::AdministrativeBlock::ACTIVE_STATE,
          copilot_access_type: :UNKNOWN,
        },
        schema: "github.copilot.v2.CopilotUserAdministrativeBlock"
      )
    end

    test "audits and publishes to hydro with passed in value" do
      user = create(:user)
      staff = create(:staff_admin_user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::ADMINISTRATIVE_BLOCK

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_administrative_block(
          copilot_user,
          staff,
          "reasons",
          access_type: :MONTHLY_SUBSCRIBER
        )
      end

      assert_subset_hash(
        {
          staff_actor_id: staff.id,
          user_id: user.id,
          action: event,
        },
        events.first,
      )

      assert_hydro_published(
        {
          staff_actor: Hydro::EntitySerializer.user(staff),
          user: Hydro::EntitySerializer.user(user),
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          block_reason: "reasons",
          state: Copilot::AdministrativeBlock::ACTIVE_STATE,
          copilot_access_type: :MONTHLY_SUBSCRIBER,
        },
        schema: "github.copilot.v2.CopilotUserAdministrativeBlock"
      )
    end

    test "audits and publishes to hydro falls back to regular access type" do
      seat = create(:copilot_seat)
      user = seat.assigned_user
      staff = create(:staff_admin_user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::ADMINISTRATIVE_BLOCK

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_administrative_block(
          copilot_user,
          staff,
          "reasons"
        )
      end

      assert_subset_hash(
        {
          staff_actor_id: staff.id,
          user_id: user.id,
          action: event,
        },
        events.first,
      )

      assert_hydro_published(
        {
          staff_actor: Hydro::EntitySerializer.user(staff),
          user: Hydro::EntitySerializer.user(user),
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          block_reason: "reasons",
          state: Copilot::AdministrativeBlock::ACTIVE_STATE,
          copilot_access_type: :COPILOT_FOR_BUSINESS_SEAT,
        },
        schema: "github.copilot.v2.CopilotUserAdministrativeBlock"
      )
    end
  end

  context "editor notification" do
    context "shown" do
      test "audits and publishes to hydro" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::EDITOR_NOTIFICATION
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_editor_notification_shown(
            copilot_user,
            "subscription_ending",
            {
              editor_version: "1.0.0",
              editor_plugin_version: "1.1.0",
            }
          )
        end

        assert_subset_hash(
          {
            user_id: user.id,
            editor_version: "1.0.0",
            editor_plugin_version: "1.1.0",
            notification_event_name: "subscription_ending",
            notification_event_type: :SHOWN,
          },
          events.first,
        )

        assert_hydro_published(
          {
            request_context: nil,
            user: Hydro::EntitySerializer.user(user),
            copilot_user_details: copilot_user.copilot_user_details,
            notification_event_type: :SHOWN,
            notification_event_name: "subscription_ending",
            editor_version: "1.0.0",
            editor_plugin_version: "1.1.0",
          },
          schema: "github.copilot.v1.CopilotEditorNotificationEvent",
        )
      end
    end

    context "acknowledged" do
      test "audits and publishes to hydro" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::EDITOR_NOTIFICATION
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_editor_notification_acknowledged(
            copilot_user,
            "subscription_ending",
          )
        end

        assert_subset_hash(
          {
            user_id: user.id,
            notification_event_name: "subscription_ending",
            notification_event_type: :ACKNOWLEDGED,
          },
          events.first,
        )

        assert_hydro_published(
          {
            request_context: nil,
            user: Hydro::EntitySerializer.user(user),
            copilot_user_details: copilot_user.copilot_user_details,
            notification_event_type: :ACKNOWLEDGED,
            notification_event_name: "subscription_ending",
          },
          schema: "github.copilot.v1.CopilotEditorNotificationEvent",
        )
      end
    end
  end

  context "free user event" do
    context "cancelled" do
      test "audits and publishes to hydro" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::FREE_USER_EVENT
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_free_user_cancelled(copilot_user)
        end

        assert_subset_hash(
          {
            user_id: user.id,
            free_user_event_type: :CANCELLED,
          },
          events.first,
        )

        assert_hydro_published(
          {
            user: Hydro::EntitySerializer.user(user),
            copilot_user_details: copilot_user.copilot_user_details,
            event_type: :CANCELLED,
          },
          schema: "github.copilot.v1.CopilotFreeUserEvent",
        )
      end
    end

    context "refreshed" do
      test "audits and publishes to hydro" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::FREE_USER_EVENT
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_free_user_refreshed(copilot_user)
        end

        assert_subset_hash(
          {
            free_user_event_type: :REFRESHED,
            user_id: user.id,
          },
          events.first,
        )

        assert_hydro_published(
          {
            user: Hydro::EntitySerializer.user(user),
            copilot_user_details: copilot_user.copilot_user_details,
            event_type: :REFRESHED,
          },
          schema: "github.copilot.v1.CopilotFreeUserEvent",
        )
      end
    end

    context "warned" do
      test "audits and publishes to hydro" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::FREE_USER_EVENT
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_free_user_warned(copilot_user)
        end

        assert_subset_hash(
          {
            free_user_event_type: :WARNED,
            user_id: user.id,
          },
          events.first,
        )

        assert_hydro_published(
          {
            user: Hydro::EntitySerializer.user(user),
            copilot_user_details: copilot_user.copilot_user_details,
            event_type: :WARNED,
          },
          schema: "github.copilot.v1.CopilotFreeUserEvent",
        )
      end
    end
  end

  context "settings saved" do
    test "audits and publishes to hydro" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::SETTINGS_SAVED
      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_settings_saved(
          copilot_user,
          old_settings: {
            telemetry_configuration: :ENABLED,
            snippy_setting: :SNIPPY_UNCONFIGURED,
            editor_chat_setting: :EDITOR_CHAT_UNCONFIGURED,
          },
          new_settings: {
            telemetry_configuration: :DISABLED,
            snippy_setting: :SNIPPY_DISABLED,
            editor_chat_setting: :EDITOR_CHAT_UNCONFIGURED,
          },
        )
      end

      assert_subset_hash(
        {
          user_id: user.id,
          old_settings: {
            telemetry_configuration: "enabled",
            public_code_suggestions: "unconfigured",
            editor_chat: "unconfigured",
          },
          new_settings: {
            telemetry_configuration: "disabled",
            public_code_suggestions: "allowed",
            editor_chat: "unconfigured",
          },
        },
        events.first,
      )

      assert_hydro_published(
        {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          user: Hydro::EntitySerializer.user(user),
          copilot_user_details: copilot_user.copilot_user_details,
          old_settings: {
            telemetry_configuration: :ENABLED,
            snippy_setting: :SNIPPY_UNCONFIGURED,
            editor_chat_setting: :EDITOR_CHAT_UNCONFIGURED,
          },
          new_settings: {
            telemetry_configuration: :DISABLED,
            snippy_setting: :SNIPPY_DISABLED,
            editor_chat_setting: :EDITOR_CHAT_UNCONFIGURED,
          },
        },
        schema: "github.copilot.v1.CopilotSettingsSaved")
    end
  end

  context "signup" do
    context "free page viewed" do
      test "publishes to hydro" do
        user = create(:user, :with_instrumentation)
        copilot_user = Copilot::User.new(user)

        Copilot::Instrumenter.instrument_signup_free_page_view(
          copilot_user,
          utm_query_params: {
            utm_source: "source",
            utm_medium: "medium",
            utm_campaign: "campaign",
            utm_term: "term",
            utm_content: "content",
          },
        )

        assert_performed_audit_entries(
          count: 0,
          only: Copilot::Events::SIGNUP_FREE_PAGE_VIEW,
        )

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            user: Hydro::EntitySerializer.user(user),
            copilot_analytics: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
            copilot_user_details: copilot_user.copilot_user_details,
          },
          schema: "github.copilot.v1.CopilotSignupFreePageViewed",
        )
      end

      test "allows empty strings" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        Copilot::Instrumenter.instrument_signup_free_page_view(
          copilot_user,
          utm_query_params: {
            utm_source: "",
            utm_medium: "",
            utm_campaign: "",
            utm_term: "",
            utm_content: "",
          }
        )

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            user: Hydro::EntitySerializer.user(user),
            copilot_analytics: {
              utm_source: "",
              utm_medium: "",
              utm_campaign: "",
              utm_term: "",
              utm_content: "",
            },
            copilot_user_details: copilot_user.copilot_user_details,
          },
          schema: "github.copilot.v1.CopilotSignupFreePageViewed",
        )
      end
    end

    context "free subscription created" do
      test "audits and publishes to hydro" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::SIGNUP_FREE_SUBSCRIPTION_CREATED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_signup_free_subscription_created(
            copilot_user,
            utm_query_params: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
          )
        end

        assert_subset_hash(
          {
            user_id: user.id,
          },
          events.first,
        )

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            user: Hydro::EntitySerializer.user(user),
            copilot_analytics: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
            copilot_user_details: copilot_user.copilot_user_details,
          },
          schema: "github.copilot.v1.CopilotSignupFreeSubscriptionCreated",
        )
      end

      test "allows empty strings" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::SIGNUP_FREE_SUBSCRIPTION_CREATED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_signup_free_subscription_created(
            copilot_user,
            utm_query_params: {
              utm_source: "",
              utm_medium: "",
              utm_campaign: "",
              utm_term: "",
              utm_content: "",
            },
          )
        end

        assert_subset_hash(
          {
            user_id: user.id,
          },
          events.first,
        )

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            user: Hydro::EntitySerializer.user(user),
            copilot_analytics: {
              utm_source: "",
              utm_medium: "",
              utm_campaign: "",
              utm_term: "",
              utm_content: "",
            },
            copilot_user_details: copilot_user.copilot_user_details,
          },
          schema: "github.copilot.v1.CopilotSignupFreeSubscriptionCreated",
        )
      end
    end

    context "page viewed" do
      test "publishes to hydro" do
        user = create(:user, :with_instrumentation)
        copilot_user = Copilot::User.new(user)

        Copilot::Instrumenter.instrument_signup_page_view(
          copilot_user,
          utm_query_params: {
            utm_source: "source",
            utm_medium: "medium",
            utm_campaign: "campaign",
            utm_term: "term",
            utm_content: "content",
          },
        )

        assert_performed_audit_entries(
          count: 0,
          only: Copilot::Events::SIGNUP_PAGE_VIEW,
        )

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            user: Hydro::EntitySerializer.user(user),
            copilot_analytics: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
            copilot_user_details: copilot_user.copilot_user_details,
          },
          schema: "github.copilot.v1.CopilotSignupPageViewed",
        )
      end

      context "dogstats" do
        test "commercial interaction restriction" do
          profile = create(:account_screening_profile, :with_populated_attributes)
          user = profile.user
          enable_feature_flag(:live_sdn_screening, user)
          user.trade_screening_record.update!(msft_trade_screening_status: "lic_r")

          copilot_user = Copilot::User.new(user)

          Copilot::Instrumenter.instrument_signup_page_view(
            copilot_user,
          )

          assert_dogstats_increment 1, "copilot.signup-page-view", tags: [
            "variation:commercial_interaction_restriction",
            "subscription_ended:false",
            "technical_preview_user:false",
            "technical_preview_user_lost_access:false",
          ]
        end

        test "standard" do
          user = create(:user)
          copilot_user = Copilot::User.new(user)

          Copilot::Instrumenter.instrument_signup_page_view(
            copilot_user,
          )

          assert_dogstats_increment 1, "copilot.signup-page-view", tags: [
            "variation:standard",
            "subscription_ended:false",
            "technical_preview_user:false",
            "technical_preview_user_lost_access:false",
          ]
        end

        test "renewal" do
          copilot_monthly_product_uuid = create(
            :billing_product_uuid,
            :copilot,
            billing_cycle: :month,
          )
          plan_subscription = create(
            :billing_subscription_item,
            :paid,
            plan_subscription: create(:billing_plan_subscription, :zuora),
            subscribable: copilot_monthly_product_uuid,
            free_trial_ends_on: 2.months.ago,
            quantity: 0,
            created_at: 3.months.ago
          )
          user = plan_subscription.user
          copilot_user = Copilot::User.new(user)

          Copilot::Instrumenter.instrument_signup_page_view(
            copilot_user,
          )

          assert_dogstats_increment 1, "copilot.signup-page-view", tags: [
            "variation:renewal",
            "subscription_ended:true",
            "technical_preview_user:false",
            "technical_preview_user_lost_access:false",
          ]
        end

        test "renewal from TPU" do
          user = create(:user)
          create(:copilot_technical_preview_user, user: user, subscribed: true)
          copilot_user = Copilot::User.new(user)

          Copilot::Instrumenter.instrument_signup_page_view(
            copilot_user,
          )

          assert_dogstats_increment 1, "copilot.signup-page-view", tags: [
            "variation:renewal",
            "subscription_ended:false",
            "technical_preview_user:true",
            "technical_preview_user_lost_access:false",
          ]
        end

        test "renewal from TPU who lost access" do
          user = create(:user)
          create(:copilot_technical_preview_user, user: user, subscribed: false)
          copilot_user = Copilot::User.new(user)

          Copilot::Instrumenter.instrument_signup_page_view(
            copilot_user,
          )

          assert_dogstats_increment 1, "copilot.signup-page-view", tags: [
            "variation:renewal",
            "subscription_ended:false",
            "technical_preview_user:true",
            "technical_preview_user_lost_access:true",
          ]
        end
      end
    end

    context "plan chosen" do
      test "audits publishes to hydro" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::SIGNUP_PLAN_CHOSEN
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_signup_plan_chosen(
            copilot_user,
            "month",
            utm_query_params: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
          )
        end

        assert_subset_hash(
          {
            user_id: user.id,
            chosen_plan: "month",
          },
          events.first,
        )

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            user: Hydro::EntitySerializer.user(user),
            copilot_analytics: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
            copilot_user_details: copilot_user.copilot_user_details,
            chosen_plan: :MONTHLY,
          },
          schema: "github.copilot.v1.CopilotSignupPlanChosen",
        )
      end
    end

    context "settings saved" do
      test "audits and publishes to hydro" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::SIGNUP_SETTINGS_SAVED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_signup_settings_saved(
            copilot_user,
            utm_query_params: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
            old_settings: {
              telemetry_configuration: :ENABLED,
              snippy_setting: :SNIPPY_UNCONFIGURED,
            },
            new_settings: {
              telemetry_configuration: :DISABLED,
              snippy_setting: :SNIPPY_DISABLED,
            }
          )
        end

        assert_subset_hash(
          {
            user_id: user.id,
            old_settings: {
              telemetry_configuration: "enabled",
              public_code_suggestions: "unconfigured",
            },
            new_settings: {
              telemetry_configuration: "disabled",
              public_code_suggestions: "allowed",
            }
          },
          events.first,
        )

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            user: Hydro::EntitySerializer.user(user),
            copilot_user_details: copilot_user.copilot_user_details,
            copilot_analytics: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
            old_settings: {
              telemetry_configuration: :ENABLED,
              snippy_setting: :SNIPPY_UNCONFIGURED,
            },
            new_settings: {
              telemetry_configuration: :DISABLED,
              snippy_setting: :SNIPPY_DISABLED,
            },
          },
          schema: "github.copilot.v1.CopilotSignupSettingsSaved",
        )
      end
    end

    context "subscription created" do
      test "audits and publishes to hydro" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        event = Copilot::Events::SIGNUP_SUBSCRIPTION_CREATED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_signup_subscription_created(
            copilot_user,
            "month",
            60,
            utm_query_params: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
          )
        end

        assert_subset_hash(
          {
            user_id: user.id,
            copilot_subscription_plan: "month",
            trial_length: 60,
          },
          events.first,
        )

        assert_hydro_published(
          {
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            user: Hydro::EntitySerializer.user(user),
            copilot_analytics: {
              utm_source: "source",
              utm_medium: "medium",
              utm_campaign: "campaign",
              utm_term: "term",
              utm_content: "content",
            },
            copilot_user_details: copilot_user.copilot_user_details,
            copilot_subscription_plan: :MONTHLY,
            trial_length: 60,
          },
          schema: "github.copilot.v1.CopilotSignupSubscriptionCreated",
        )
      end
    end
  end

  context "subscription cancelled" do
    test "audits and publishes to hydro" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::SUBSCRIPTION_CANCELLED
      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_subscription_cancelled(
          copilot_user,
          "month",
          in_trial: true,
        )
      end

      assert_subset_hash(
        {
          user_id: user.id,
          in_trial: true,
          subscription_plan: "month",
        },
        events.first,
      )

      assert_hydro_published(
        {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          user: Hydro::EntitySerializer.user(user),
          copilot_user_details: copilot_user.copilot_user_details,
          in_trial: true,
          subscription_plan: :MONTHLY,
        },
        schema: "github.copilot.v1.CopilotSubscriptionCancelled",
      )
    end

    test "it is subscribed to the billing event when they cancel" do
      item = create :billing_subscription_item, subscribable: @product_uuid_subscribable, quantity: 1

      account = item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: @product_uuid_subscribable,
        quantity: 0,
        sender: account,
        plan_subscription: item.plan_subscription

      copilot_user = Copilot::User.new(account.reload)

      assert_hydro_published(
        {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          user: Hydro::EntitySerializer.user(account),
          copilot_user_details: copilot_user.copilot_user_details,
          in_trial: false,
          subscription_plan: :MONTHLY,
        },
        schema: "github.copilot.v1.CopilotSubscriptionCancelled"
      )
    end

    test "cancelled hydro event when the subscription item is destroyed" do
      item = create :billing_subscription_item,
      subscribable: @product_uuid_subscribable,
      quantity: 1

      account = item.account
      # The destruction only sets the actor from the context (normally a controller action's current user)
      GitHub.context.push(actor_id: account.id)

      copilot_user = Copilot::User.new(account.reload)
      copilot_user_details = copilot_user.copilot_user_details

      item.destroy

      assert_hydro_published(
        {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          user: Hydro::EntitySerializer.user(account),
          copilot_user_details: copilot_user_details,
          in_trial: false,
          subscription_plan: :MONTHLY,
        },
        schema: "github.copilot.v1.CopilotSubscriptionCancelled"
      )
    end

    test "it is NOT subscribed to the billing event when they convert free trial" do
      item = create :billing_subscription_item, subscribable: @product_uuid_subscribable, quantity: 1

      account = item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: @yearly_product_uuid_subscribable,
        quantity: 1,
        sender: account,
        plan_subscription: item.plan_subscription

      refute_hydro_messages(schema: "github.copilot.v1.CopilotSubscriptionCancelled")
    end
  end

  context "subscription trial converts to paid" do
    test "audits and publishes to hydro" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::TRIAL_SUBSCRIPTION_CONVERTS
      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_trial_subscription_converts(
          copilot_user,
          "month",
        )
      end

      assert_subset_hash(
        {
          user_id: user.id,
          subscription_plan: "month",
        },
        events.first,
      )

      assert_hydro_published(
        {
          user: Hydro::EntitySerializer.user(user),
          copilot_user_details: copilot_user.copilot_user_details,
          subscription_plan: :MONTHLY,
        },
        schema: "github.copilot.v1.CopilotSubscriptionTrialConvertsToPaid",
      )
    end

    test "handles the billing event when they convert free trial" do
      item = create :billing_subscription_item, subscribable: @product_uuid_subscribable, quantity: 1

      account = item.account

      Billing::SubscriptionItemUpdater.perform \
        subscribable: @product_uuid_subscribable,
        end_free_trial: true,
        quantity: 1,
        sender: account,
        plan_subscription: item.plan_subscription

      copilot_user = Copilot::User.new(account.reload)

      assert_hydro_published(
        {
          user: Hydro::EntitySerializer.user(account),
          copilot_user_details: copilot_user.copilot_user_details,
          subscription_plan: :MONTHLY,
        },
        schema: "github.copilot.v1.CopilotSubscriptionTrialConvertsToPaid",
      )
    end
  end

  context "token failures" do
    test "audits and publishes to hydro" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::TOKEN_FAILURE
      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_token_failed(
          copilot_user,
          "dlsfkjslk",
          {
            editor_version: "1.0.0",
            editor_plugin_version: "1.1.0",
          },
        )
      end

      assert_subset_hash(
        {
          user_id: user.id,
          editor_version: "1.0.0",
          editor_plugin_version: "1.1.0",
          failure_reason: "dlsfkjslk",
        },
        events.first,
      )

      assert_hydro_published(
        {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(user),
          failure_reason: "dlsfkjslk",
          editor_version: "1.0.0",
          editor_plugin_version: "1.1.0",
          copilot_user_details: copilot_user.copilot_user_details,
        },
        schema: "github.copilot.v0.CopilotTokenFailure",
      )
    end
  end

  context "token generation" do
    test "audits and publishes to hydro only" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      seat = create(:copilot_seat)
      user = seat.assigned_user
      copilot_user = Copilot::User.new(user)
      expires_at = 1000
      assert_equal :COPILOT_FOR_BUSINESS_SEAT, copilot_user.copilot_authorizer_object.access_type

      assert_performed_audit_entries(count: 0) do
        Copilot::Instrumenter.instrument_token_generated(
          copilot_user,
          expires_at,
          copilot_user.copilot_authorizer_object.access_type,
          {
            editor_version: "1.0.0",
            editor_plugin_version: "1.1.0",
          },
          copilot_user.organization_list,
        )
      end

      assert_hydro_published(
        {
          actor_analytics_tracking_id: user.analytics_tracking_id,
          actor: Hydro::EntitySerializer.user(user),
          copilot_access_type: copilot_user.copilot_authorizer_object.access_type,
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          editor_plugin_version: "1.1.0",
          editor_version: "1.0.0",
          expires_at: expires_at,
          free_enterprise_organization_name: nil,
          organization_analytics_tracking_ids: seat.organization.analytics_tracking_id,
          other_free_access_type: nil,
          partner_organization_name: nil,
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          source: "token_generation",
        },
        schema: "github.copilot.v0.CopilotTokenGenerated",
      )
    end

    test "audits and publishes to hydro only with a free limited user" do
      limited_user = create(:copilot_limited_user, subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key("chat"), 10)
      Copilot.limiter_redis.set(limited_user.feature_count_key("completions"), 1000)

      user = limited_user.user
      user.emails.map(&:verify!)
      copilot_user = Copilot::User.new(user)
      expires_at = 1000

      assert_performed_audit_entries(count: 0) do
        Copilot::Instrumenter.instrument_token_generated(
          copilot_user,
          expires_at,
          copilot_user.copilot_authorizer_object.access_type,
          {
            editor_version: "1.0.0",
            editor_plugin_version: "1.1.0",
          },
          copilot_user.organization_list,
        )
      end

      assert_hydro_published(
        {
          actor_analytics_tracking_id: user.analytics_tracking_id,
          actor: Hydro::EntitySerializer.user(user),
          copilot_access_type: copilot_user.copilot_authorizer_object.access_type,
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          editor_plugin_version: "1.1.0",
          editor_version: "1.0.0",
          expires_at: expires_at,
          free_enterprise_organization_name: nil,
          organization_analytics_tracking_ids: nil,
          other_free_access_type: nil,
          partner_organization_name: nil,
          quota_details: [{ feature: "chat", percentage: 98.0, quota: 490 }, { feature: "completions", percentage: 50.0, quota: 1000 }],
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          source: "token_generation",
        },
        schema: "github.copilot.v0.CopilotTokenGenerated",
      )
    end

    test "audits and publishes to hydro only with seat assignment" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      assignment = create(:copilot_seat_assignment, :user)
      user = assignment.assignable
      copilot_user = Copilot::User.new(user)
      expires_at = 1000
      assert_equal :COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT, copilot_user.copilot_authorizer_object.access_type
      assert_equal 0, Copilot::Seat.count

      assert_performed_audit_entries(count: 0) do
        Copilot::Instrumenter.instrument_token_generated(
          copilot_user,
          expires_at,
          copilot_user.copilot_authorizer_object.access_type,
          {
            editor_version: "1.0.0",
            editor_plugin_version: "1.1.0",
          },
          copilot_user.organization_list,
        )
      end

      assert_hydro_published(
        {
          actor_analytics_tracking_id: user.analytics_tracking_id,
          actor: Hydro::EntitySerializer.user(user),
          copilot_access_type: copilot_user.copilot_authorizer_object.access_type,
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          editor_plugin_version: "1.1.0",
          editor_version: "1.0.0",
          expires_at: expires_at,
          free_enterprise_organization_name: nil,
          organization_analytics_tracking_ids: assignment.organization.analytics_tracking_id,
          other_free_access_type: nil,
          partner_organization_name: nil,
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          source: "token_generation",
        },
        schema: "github.copilot.v0.CopilotTokenGenerated",
      )
    end

    test "audits and publishes to hydro only with copilot_plan enterprise seat assignment" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      assignment = create(:copilot_seat_assignment, :user, copilot_plan: "enterprise")
      user = assignment.assignable
      copilot_user = Copilot::User.new(user)
      expires_at = 1000
      assert_equal :COPILOT_ENTERPRISE_SEAT_ASSIGNMENT, copilot_user.copilot_authorizer_object.access_type
      assert_equal 0, Copilot::Seat.count

      assert_performed_audit_entries(count: 0) do
        Copilot::Instrumenter.instrument_token_generated(
          copilot_user,
          expires_at,
          copilot_user.copilot_authorizer_object.access_type,
          {
            editor_version: "1.0.0",
            editor_plugin_version: "1.1.0",
          },
          copilot_user.organization_list,
        )
      end

      assert_hydro_published(
        {
          actor_analytics_tracking_id: user.analytics_tracking_id,
          actor: Hydro::EntitySerializer.user(user),
          copilot_access_type: copilot_user.copilot_authorizer_object.access_type,
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          editor_plugin_version: "1.1.0",
          editor_version: "1.0.0",
          expires_at: expires_at,
          free_enterprise_organization_name: nil,
          organization_analytics_tracking_ids: assignment.organization.analytics_tracking_id,
          other_free_access_type: nil,
          partner_organization_name: nil,
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          source: "token_generation",
        },
        schema: "github.copilot.v0.CopilotTokenGenerated",
      )
    end

    test "audits and publishes to hydro only with standalone seat assignment" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = assignment.assignable
      user = User.find(enterprise_team.member_user_ids.first)
      copilot_user = Copilot::User.new(user)
      expires_at = 1000
      assert_equal :COPILOT_STANDALONE_SEAT_ASSIGNMENT, copilot_user.copilot_authorizer_object.access_type
      assert_equal 0, Copilot::Seat.count

      assert_performed_audit_entries(count: 0) do
        Copilot::Instrumenter.instrument_token_generated(
          copilot_user,
          expires_at,
          copilot_user.copilot_authorizer_object.access_type,
          {
            editor_version: "1.0.0",
            editor_plugin_version: "1.1.0",
          },
          copilot_user.organization_list,
        )
      end

      assert_hydro_published(
        {
          actor_analytics_tracking_id: user.analytics_tracking_id,
          actor: Hydro::EntitySerializer.user(user),
          copilot_access_type: copilot_user.copilot_authorizer_object.access_type,
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          editor_plugin_version: "1.1.0",
          editor_version: "1.0.0",
          expires_at: expires_at,
          free_enterprise_organization_name: nil,
          organization_analytics_tracking_ids: nil,
          other_free_access_type: nil,
          partner_organization_name: nil,
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          source: "token_generation",
        },
        schema: "github.copilot.v0.CopilotTokenGenerated",
      )
    end

    test "the source can be passed through" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = assignment.assignable
      user = User.find(enterprise_team.member_user_ids.first)
      copilot_user = Copilot::User.new(user)
      expires_at = 1000
      assert_equal :COPILOT_STANDALONE_SEAT_ASSIGNMENT, copilot_user.copilot_authorizer_object.access_type
      assert_equal 0, Copilot::Seat.count

      assert_performed_audit_entries(count: 0) do
        Copilot::Instrumenter.instrument_token_generated(
          copilot_user,
          expires_at,
          copilot_user.copilot_authorizer_object.access_type,
          {
            editor_version: "1.0.0",
            editor_plugin_version: "1.1.0",
          },
          copilot_user.organization_list,
          source: "source",
        )
      end

      assert_hydro_published(
        {
          actor_analytics_tracking_id: user.analytics_tracking_id,
          actor: Hydro::EntitySerializer.user(user),
          copilot_access_type: copilot_user.copilot_authorizer_object.access_type,
          copilot_user_details: copilot_user.copilot_user_details(include_trust_tier: true),
          editor_plugin_version: "1.1.0",
          editor_version: "1.0.0",
          expires_at: expires_at,
          free_enterprise_organization_name: nil,
          organization_analytics_tracking_ids: nil,
          other_free_access_type: nil,
          partner_organization_name: nil,
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          source: "source",
        },
        schema: "github.copilot.v0.CopilotTokenGenerated",
      )
    end
  end

  context "complimentary access granted" do
    test "audits and publishes to hydro" do
      user = create(:user)
      staff = create(:staff_admin_user)
      copilot_user = Copilot::User.new(user)

      event = Copilot::Events::COMPLIMENTARY_ACCESS_GRANTED

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_free_access_granted(
          user,
          staff,
          Copilot::FreeUser::COMPLIMENTARY_ACCESS.name,
          Date.new(0000),
          "reasons",
        )
      end

      assert_subset_hash(
        {
          staff_actor_id: staff.id,
          user_id: user.id,
          action: "copilot.complimentary_access_granted",
        },
        events.first,
      )

      assert_hydro_published(
        {
          user: Hydro::EntitySerializer.user(user),
          staff_actor: Hydro::EntitySerializer.user(staff),
          copilot_user_details: copilot_user.copilot_user_details,
          free_user_type: :COMPLIMENTARY_ACCESS,
          complimentary_access_duration: "0000-01-01",
          complimentary_access_reason_explanation: "reasons",
        },
        schema: "github.copilot.v1.CopilotComplimentaryAccessGrantedEvent"
      )
    end
  end

  context "limited user subscribes" do
    test "publishes to hydro" do
      user = create(:user)
      create(:copilot_limited_user, user: user)
      copilot_user = Copilot::User.new(user)

      Copilot::Instrumenter.instrument_signup_limited_subscription_created(
        copilot_user,
        utm_query_params: {
          utm_source: "source",
          utm_medium: "medium",
          utm_campaign: "campaign",
          utm_term: "term",
          utm_content: "content",
        },
      )

      assert_hydro_published(
        {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          user: Hydro::EntitySerializer.user(user),
          copilot_analytics: {
            utm_source: "source",
            utm_medium: "medium",
            utm_campaign: "campaign",
            utm_term: "term",
            utm_content: "content",
          },
          copilot_user_details: copilot_user.copilot_user_details,
        },
        schema: "github.copilot.v3.CopilotLimitedUserSubscribed",
      )
    end
  end
end if GitHub.copilot_enabled?
