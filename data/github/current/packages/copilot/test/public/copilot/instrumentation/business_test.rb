# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Instrumentation::BusinessTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @product_uuid_subscribable ||= create(:billing_product_uuid, :copilot)
    @yearly_product_uuid_subscribable = create(:billing_product_uuid, :copilot, billing_cycle: :year)
  end

  context "token_generated" do
    test "audits and publishes to hydro only with telemetry snapshot" do
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
  end

  context "click wrap saved" do
    test "audits and publishes to hydro" do
      actor = create(:user)
      biz = create(:business)

      event = Copilot::Events::COPILOT_FOR_BUSINESS_CLICKWRAP_SAVED
      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_clickwrap_saved(
          actor,
          biz,
        )
      end

      assert_subset_hash(
        {
          actor: actor.display_login,
          business_id: biz.id,
          business: biz.display_login,
          terms_type: "product"
        },
        events.first
      )

      assert_hydro_published(
        {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(actor),
          business: Hydro::EntitySerializer.business(biz),
        },
        schema: "github.copilot.v2.CopilotClickwrapSavedEvent",
      )
    end
  end

  context "click wrap shown" do
    test "audits and publishes to hydro" do
      actor = create(:user)
      biz = create(:business)

      Copilot::Instrumenter.instrument_clickwrap_shown(
        actor,
        biz,
      )

      assert_hydro_published(
        {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(actor),
          business: Hydro::EntitySerializer.business(biz),
        },
        schema: "github.copilot.v2.CopilotClickwrapShownEvent",
      )
    end
  end

  context "instrument_enterprise_settings_changed" do
    test "publishes to hydro and audit log" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      actor = organization.admins.first

      business = organization.business
      copilot_business = Copilot::Business.new(business)
      old_settings = copilot_business.copilot_business_settings
      copilot_business.no_public_code_suggestions_policy!
      copilot_business.disable_chat!
      new_settings = copilot_business.copilot_business_settings

      event = ::Copilot::Events::COPILOT_FOR_BUSINESS_ENTERPRISE_SETTINGS_CHANGED
      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_enterprise_settings_changed(
          actor,
          business,
          old_settings: old_settings,
          new_settings: new_settings,
        )
      end

      old_settings_audit_hash = {
        cli: "enabled",
        desktop: "enabled",
        editor_preview_features: "unconfigured",
        a_chat: "unconfigured",
        af: "unconfigured",
        g_chat: "unconfigured",
        o1: "unconfigured",
        o3: "unconfigured",
        off: "unconfigured",
        of: "unconfigured",
        copilot_beta_features_opt_in: "disabled",
        copilot_extensions: "unconfigured",
        copilot: "all_organizations",
        editor_chat: "enabled",
        github_chat_bing_access: "no_policy",
        github_chat: "enabled",
        mobile_chat: "enabled",
        pr_summarizations: "enabled",
        public_code_suggestions: "blocked",
        workspace_for_emu: "disabled",
        overages: "unconfigured",
      }
      new_settings_audit_hash = {
        cli: "enabled",
        desktop: "enabled",
        editor_preview_features: "unconfigured",
        a_chat: "unconfigured",
        af: "unconfigured",
        g_chat: "unconfigured",
        o1: "unconfigured",
        o3: "unconfigured",
        off: "unconfigured",
        of: "unconfigured",
        copilot_beta_features_opt_in: "disabled",
        copilot_extensions: "unconfigured",
        copilot: "all_organizations",
        editor_chat: "disabled",
        github_chat_bing_access: "no_policy",
        github_chat: "enabled",
        mobile_chat: "enabled",
        pr_summarizations: "enabled",
        public_code_suggestions: "no_policy",
        workspace_for_emu: "disabled",
        overages: "unconfigured",
      }

      assert_subset_hash(
        {
          business: business.display_login,
          old_settings: old_settings_audit_hash,
          new_settings: new_settings_audit_hash,
          actor: actor.display_login
        },
        events.first
      )

      assert_hydro_published(
        {
          actor: Hydro::EntitySerializer.user(actor),
          business: Hydro::EntitySerializer.business(business),
          old_settings: Hydro::EntitySerializer.copilot_business_settings(old_settings),
          new_settings: Hydro::EntitySerializer.copilot_business_settings(new_settings),
        },
        schema: "github.copilot.v2.CopilotForBusinessEnterpriseSettingsChanged",
      )
    end
  end

  context "instrument_copilot_for_business_individual_seat_converted" do
    test "publishes to hydro" do
      Timecop.freeze do
        copilot_monthly_product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month).freeze

        plan_subscription = create(:billing_plan_subscription, :zuora)
        plan_user = plan_subscription.user

        subscription_item = Billing::Public::SubscriptionItem.create(
          product: copilot_monthly_product_identifier,
          account: plan_user,
          actor: plan_user,
          free_trial_length: 0.days
        ).value!

        organization = create(:copilot_for_business_enabled_organization)
        organization.add_member(plan_user)

        seat = create(:copilot_seat, assigned_user: plan_user, organization: organization)

        details = {
          spaghetti: "western",
        }

        Copilot::Instrumenter.instrument_copilot_for_business_individual_seat_converted(
          plan_user,
          subscription_item,
          seat,
          details,
        )

        copilot_user = Copilot::User.new(plan_user)
        other_cfb_org_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s
        assert_hydro_published(
          {
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details(details),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            other_cfb_organization_analytics_tracking_ids: other_cfb_org_tracking_ids,
            seat: Hydro::EntitySerializer.copilot_seat(seat),
            subscription_duration: subscription_item.interval.to_s,
            subscription_item_id: subscription_item.id,
            user: Hydro::EntitySerializer.user(plan_user),
          },
          schema: "github.copilot.v2.CopilotForBusinessIndividualSeatConverted",
        )
      end
    end
  end

  context "instrument_organization_settings_changed" do
    test "publishes to hydro" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      actor = organization.admins.first

      copilot_organization = Copilot::Organization.new(organization)
      old_settings = copilot_organization.copilot_organization_settings
      copilot_organization.allow_public_code_suggestions!
      new_settings = copilot_organization.copilot_organization_settings

      Copilot::Instrumenter.instrument_organization_settings_changed(
        organization,
        actor,
        old_settings: old_settings,
        new_settings: new_settings,
      )

      assert_hydro_published(
        {
          owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
          actor: Hydro::EntitySerializer.user(actor),
          old_settings_value: Hydro::EntitySerializer.copilot_organization_settings(old_settings),
          new_settings_value: Hydro::EntitySerializer.copilot_organization_settings(new_settings),
        },
        schema: "github.copilot.v2.CopilotForBusinessOrganizationSettingsChanged",
      )
    end
  end

  context "copilot_for_business_seat_added" do
    test "publishes to hydro" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      actor = organization.admins.first
      seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: actor)
      seat = create(:copilot_seat, organization: organization, seat_assignment: seat_assignment, assigned_user: user)

      copilot_user = Copilot::User.new(user)
      other_cfb_org_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s

      event = Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ADDED
      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_copilot_for_business_seat_added(
          organization,
          user.id,
          actor,
          :batch_insert,
          spaghetti: "western",
          shark: "nado",
        )
      end

      assert_subset_hash(
        {
          user_id: user.id,
          org_id: organization.id, # this needs to be there dude
        },
        events.first
      )

      assert_hydro_published(
        {
          user: Hydro::EntitySerializer.user(user),
          owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
          seat: Hydro::EntitySerializer.copilot_seat(seat),
          other_cfb_organization_analytics_tracking_ids: other_cfb_org_tracking_ids,
          actor: Hydro::EntitySerializer.user(actor),
          event_type: "batch_insert",
          copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
        },
        schema: "github.copilot.v2.CopilotForBusinessSeatAdded",
      )
    end
  end

  context "copilot_for_business_seat_assignment_conversion" do
    test "publishes to hydro" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      actor = organization.admins.first
      seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: actor)

      Copilot::Instrumenter.instrument_copilot_for_business_assignment_conversion(
        seat_assignment,
        0,
        0,
        0,
      )

      assert_hydro_published(
        {
          assignment: Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment),
          owner_details: Hydro::EntitySerializer.copilot_owner_details(seat_assignment.owner),
          existing_seats_count: 0,
          matched_existing_seat_count: 0,
          seat_to_insert_count: 0,
        },
        schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentConversion",
      )
    end
  end

  context "copilot_for_business_seat_assignment_created" do
    test "publishes to hydro and audit log for a user" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        organization.add_member(user)
        actor = organization.admins.first
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: actor)

        event = Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_CREATED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_created(
            seat_assignment,
            actor,
            :direct_assignment,
            spaghetti: "western",
            shark: "nado",
          )
        end

        assert_subset_hash(
          {
            seat_assignment: {
              access_revoked_at: nil,
              assignee_type: "User",
              assignee: user.display_login,
              pending_cancellation_date: seat_assignment.pending_cancellation_date&.iso8601,
              created_at: seat_assignment.created_at.iso8601,
            },
            user: user.display_login,
            user_id: user.id,
            actor: actor.display_login,
            actor_id: actor.id,
          },
          events.first
        )

        assert_hydro_published(
          {
            assignment: Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            actor: Hydro::EntitySerializer.user(actor),
            event_type: "direct_assignment",
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated",
        )
      end
    end

    test "publishes to hydro and audit log for a team" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        team = create(:team, organization: organization)
        user = create(:user)
        organization.add_member(user)
        team.add_member(user)
        actor = organization.admins.first
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: team, assigning_user: actor)

        event = Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_CREATED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_created(
            seat_assignment,
            actor,
            :direct_assignment,
            spaghetti: "western",
            shark: "nado",
          )
        end

        assert_subset_hash(
          {
            seat_assignment: {
              access_revoked_at: nil,
              assignee_type: "Team",
              assignee: team.name,
              pending_cancellation_date: seat_assignment.pending_cancellation_date&.iso8601,
              created_at: seat_assignment.created_at.iso8601,
            },
            actor: actor.display_login,
            actor_id: actor.id,
          },
          events.first
        )

        assert_hydro_published(
          {
            assignment: Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            actor: Hydro::EntitySerializer.user(actor),
            event_type: "direct_assignment",
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentCreated",
        )
      end
    end
  end

  context "copilot_for_business_seat_assignment_refreshed" do
    test "publishes to hydro and audit log" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        organization.add_member(user)
        actor = organization.admins.first
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: actor)

        event = Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_REFRESHED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_refreshed(
            seat_assignment,
            actor,
            spaghetti: "western",
            shark: "nado",
          )
        end

        assert_subset_hash(
          {
            seat_assignment: {
              access_revoked_at: nil,
              assignee_type: "User",
              assignee: user.display_login,
              pending_cancellation_date: nil,
              created_at: seat_assignment.created_at.iso8601,
            },
            user: user.display_login,
            user_id: user.id,
            actor: actor.display_login,
            actor_id: actor.id,
          },
          events.first
        )

        assert_hydro_published(
          {
            assignment: Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            actor: Hydro::EntitySerializer.user(actor),
            event_type: "refresh",
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentRefreshed",
        )
      end
    end
  end

  context "copilot_for_business_seat_assignment_reused" do
    test "publishes to hydro" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        organization.add_member(user)
        actor = organization.admins.first
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: actor)

        event = Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_REUSED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_reused(
            seat_assignment,
            actor,
            spaghetti: "western",
            shark: "nado",
          )
        end

        assert_subset_hash(
          {
            seat_assignment: {
              access_revoked_at: nil,
              assignee_type: "User",
              assignee: seat_assignment.assignable.display_login,
              pending_cancellation_date: nil,
              created_at: seat_assignment.created_at.iso8601,
            },
            user: user.display_login,
            user_id: user.id,
            actor: actor.display_login,
            actor_id: actor.id,
          },
          events.first
        )

        assert_hydro_published(
          {
            assignment: Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            actor: Hydro::EntitySerializer.user(actor),
            event_type: "reuse",
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentReused",
        )
      end
    end
  end

  context "copilot_for_business_seat_assignment_unassigned" do
    test "publishes to hydro and audit log" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        organization.add_member(user)
        actor = organization.admins.first

        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: actor)
        seat_assignment.unassign!(actor)

        event = Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT_UNASSIGNED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_unassigned(
            seat_assignment.reload,
            actor,
            :destroyed,
            spaghetti: "western",
            shark: "nado",
          )
        end

        assert_subset_hash(
          {
            seat_assignment: {
              access_revoked_at: nil,
              assignee_type: "User",
              assignee: user.display_login,
              pending_cancellation_date: seat_assignment.pending_cancellation_date&.iso8601,
              created_at: seat_assignment.created_at.iso8601,
            },
            actor: actor.display_login,
            actor_id: actor.id,
            user: user.display_login,
            user_id: user.id
          },
          events.first
        )

        assert_hydro_published(
          {
            assignment: Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            actor: Hydro::EntitySerializer.user(actor),
            event_type: "destroyed",
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatAssignmentUnassigned",
        )
      end
    end
  end

  context "copilot_for_business_seat_cancelled" do
    test "by staff" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        staff = create(:staff_admin_user)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: organization.admins.first)
        seat = create(:copilot_seat, organization: organization, seat_assignment: seat_assignment, assigned_user: user)

        copilot_user = Copilot::User.new(user)
        other_cfb_org_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s

        event = Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED_BY_STAFF
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_copilot_for_business_seat_cancelled(
            seat,
            staff,
            true,
            :cancel_immediately,
            spaghetti: "western",
            shark: "nado",
          )
        end

        assert_subset_hash(
          {
            org: organization.display_login,
            action: "copilot.cfb_seat_cancelled_by_staff",
            user: user.display_login,
            actor: "github-staff"
          },
          events.first
        )

        assert_hydro_published(
          {
            user: Hydro::EntitySerializer.user(user),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            seat: Hydro::EntitySerializer.copilot_seat(seat),
            other_cfb_organization_analytics_tracking_ids: other_cfb_org_tracking_ids,
            actor: Hydro::EntitySerializer.user(staff),
            event_type: "cancel_immediately",
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatCancelledByStaff",
        )
      end
    end

    test "by job" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: organization.admins.first)
        seat = create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: user)

        copilot_user = Copilot::User.new(user)
        other_cfb_org_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s

        event = Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_CANCELLED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_copilot_for_business_seat_cancelled(
            seat,
            nil,
            false,
            :event_type,
            spaghetti: "western",
            shark: "nado",
          )
        end

        assert_subset_hash(
          {
            org: organization.display_login,
            action: "copilot.cfb_seat_cancelled",
            user: user.display_login,
            actor: nil
          },
          events.first
        )

        assert_hydro_published(
          {
            user: Hydro::EntitySerializer.user(user),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            seat: Hydro::EntitySerializer.copilot_seat(seat),
            other_cfb_organization_analytics_tracking_ids: other_cfb_org_tracking_ids,
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatCancelled",
        )
      end
    end
  end

  context "copilot_for_business_seat_emission" do
    test "publishes to hydro" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        user = create(:user)
        organization.add_member(user)
        actor = organization.admins.first
        seat_assignment = create(:copilot_seat_assignment, owner: organization, assignable: user, assigning_user: actor)
        create(:copilot_seat, organization: organization, seat_assignment: seat_assignment, assigned_user: user)
        seat_emission = create(:copilot_seat_emission, owner: organization)

        already_billed_user_ids_count = 1
        number_of_days_in_billing_cycle = 30.0
        per_seat_rate = 7.0
        seat_count = 7.0

        Copilot::Instrumenter.instrument_copilot_for_business_seat_emission(
          organization,
          seat_emission,
          already_billed_user_ids_count: already_billed_user_ids_count,
          number_of_days_in_billing_cycle: number_of_days_in_billing_cycle,
          per_seat_rate: per_seat_rate,
          seat_count: seat_count,
        )

        assert_hydro_published(
          {
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            already_billed_user_ids_count: already_billed_user_ids_count,
            number_of_days_in_billing_cycle: number_of_days_in_billing_cycle,
            per_seat_rate: per_seat_rate,
            quantity: seat_emission.quantity.to_f,
            seat_count: seat_count,
            seat_emission: Hydro::EntitySerializer.copilot_seat_emission(seat_emission),
            source_uri: seat_emission.source_uri,
            usage_at: Google::Protobuf::Timestamp.new(seconds: seat_emission.usage_at.to_i, nanos: 0),
            usage_uuid: seat_emission.usage_uuid,
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatEmissionCreated",
        )
      end
    end
  end

  context "copilot_for_business_seat_emission_skipped" do
    test "publishes to hydro" do
      organization = create(:copilot_for_business_enabled_organization)

      Copilot::Instrumenter.instrument_copilot_for_business_seat_emission_skipped(
        organization,
        "because",
      )

      assert_hydro_published(
        {
          owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
          reason: "because",
        },
        schema: "github.copilot.v2.CopilotForBusinessSeatEmissionSkipped",
      )
    end
  end

  context "instrument_copilot_for_business_seat_management_changed" do
    test "publishes to hydro and audit log" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        org_admin = organization.admins.first
        old_value = "ALLOW_ALL"
        new_value = "DISABLED"

        event = ::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_MANAGEMENT_CHANGED
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_copilot_for_business_seat_management_changed(
            org_admin,
            organization,
            old_value,
            new_value,
            spaghetti: "western",
            shark: "nado",
          )
        end

        assert_subset_hash(
          {
            organization: organization.display_login,
            previous_value: old_value,
            new_value: new_value,
            actor: org_admin.display_login
          },
          events.first
        )

        assert_hydro_published(
          {
            actor: Hydro::EntitySerializer.user(org_admin),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(organization),
            previous_value: old_value,
            new_value: new_value,
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
          },
          schema: "github.copilot.v2.CopilotForBusinessOrganizationSeatManagementChanged",
        )
      end
    end
  end


  context "copilot_for_business_seat_uncancelled" do
    test "by staff" do
      Timecop.freeze do
        staff_actor = create(:user)
        seat = create(:copilot_seat)

        copilot_user = Copilot::User.new(seat.assigned_user)
        other_cfb_org_tracking_ids = copilot_user.orgs_having_copilot_for_business.collect(&:analytics_tracking_id).to_s

        event = ::Copilot::Events::COPILOT_FOR_BUSINESS_SEAT_UNCANCELLED_BY_STAFF
        events = assert_performed_audit_entries(count: 1, only: event) do
          Copilot::Instrumenter.instrument_copilot_for_business_seat_uncancelled(
            seat,
            staff_actor,
            spaghetti: "western",
            shark: "nado",
          )
        end

        assert_subset_hash(
          {
            seat: seat.audit_log_payload,
            seat_assignment: seat.seat_assignment.audit_log_payload,
            user: seat.assigned_user.display_login
          },
          events.first
        )

        assert_hydro_published(
          {
            user: Hydro::EntitySerializer.user(seat.assigned_user),
            owner_details: Hydro::EntitySerializer.copilot_owner_details(seat.organization),
            seat: Hydro::EntitySerializer.copilot_seat(seat),
            other_cfb_organization_analytics_tracking_ids: other_cfb_org_tracking_ids,
            staff_actor: Hydro::EntitySerializer.user(staff_actor),
            copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western", shark: "nado" }),
          },
          schema: "github.copilot.v2.CopilotForBusinessSeatUncancelledByStaff",
        )
      end
    end
  end

  context "copilot_business_trial_created" do
    test "publishes to hydro" do
      Timecop.freeze do
        business_trial = create(:copilot_business_trial, :organization, :active)
        staff_user = create(:user)

        seat_count = 7
        duration = 30

        Copilot::Instrumenter.instrument_copilot_business_trial_created(
          staff_user,
          business_trial.trialable,
          seat_count,
          duration,
          business_trial.copilot_plan,
        )

        assert_hydro_published(
          {
            staff_actor: Hydro::EntitySerializer.user(staff_user),
            organization: Hydro::EntitySerializer.organization(business_trial.trialable),
            business: Hydro::EntitySerializer.business(business_trial.trialable.business),
            seat_count: seat_count,
            trial_duration_days: duration,
            copilot_plan: Hydro::EntitySerializer.copilot_plan(business_trial.copilot_plan),
          },
          schema: "github.copilot.v2.CopilotForBusinessTrialCreated",
        )
      end
    end
  end

  context "copilot_business_trial_ended" do
    test "publishes to hydro" do
      Timecop.freeze do
        business_trial = create(:copilot_business_trial, :organization, :expired)
        organization = business_trial.trialable

        duration = 30

        Copilot::Instrumenter.instrument_copilot_business_trial_ended(
          organization,
        )

        assert_hydro_published(
          {
            organization: Hydro::EntitySerializer.organization(organization),
            business: Hydro::EntitySerializer.business(organization.business),
            seat_count: 0,
            trial_duration_days: duration,
            trial_started_at: Google::Protobuf::Timestamp.new(seconds: business_trial.started_at.to_i, nanos: 0),
            trial_ended_at: Google::Protobuf::Timestamp.new(seconds: business_trial.ends_at.to_i, nanos: 0),
            copilot_plan: Hydro::EntitySerializer.copilot_plan(business_trial.copilot_plan),
          },
          schema: "github.copilot.v2.CopilotForBusinessTrialEnded",
        )
      end
    end
  end

  context "copilot_business_trial_started" do
    test "publishes to hydro" do
      business_trial = create(:copilot_business_trial, :organization, :started)
      organization = business_trial.trialable

      duration = 30

      Copilot::Instrumenter.instrument_copilot_business_trial_started(
        organization.admins.first,
        business_trial
      )

      assert_hydro_published(
        {
          admin: Hydro::EntitySerializer.user(organization.admins.first),
          organization: Hydro::EntitySerializer.organization(organization),
          business: Hydro::EntitySerializer.business(organization.business),
          seat_count: 0,
          trial_duration_days: duration,
          trial_started_at: Google::Protobuf::Timestamp.new(seconds: business_trial.started_at.to_i, nanos: 0),
          trial_ends_at: Google::Protobuf::Timestamp.new(seconds: business_trial.ends_at.to_i, nanos: 0),
          copilot_plan: Hydro::EntitySerializer.copilot_plan(business_trial.copilot_plan),
        },
        schema: "github.copilot.v2.CopilotForBusinessTrialStarted",
      )
    end
  end

  context "copilot_business_trial_upgraded" do
    test "publishes to hydro" do
      business_trial = create(:copilot_business_trial, :organization, :started)
      organization = business_trial.trialable
      staff_actor = create(:user)

      duration = 30

      Copilot::Instrumenter.instrument_copilot_business_trial_upgraded(
        staff_actor,
        business_trial
      )

      assert_hydro_published(
        {
          staff_actor: Hydro::EntitySerializer.user(staff_actor),
          organization: Hydro::EntitySerializer.organization(organization),
          business: Hydro::EntitySerializer.business(organization.business),
          seat_count: 0,
          trial_duration_days: duration,
          trial_started_at: Google::Protobuf::Timestamp.new(seconds: business_trial.started_at.to_i, nanos: 0),
          trial_ended_at: Google::Protobuf::Timestamp.new(seconds: business_trial.ends_at.to_i, nanos: 0),
          copilot_plan: Hydro::EntitySerializer.copilot_plan(business_trial.copilot_plan),
        },
        schema: "github.copilot.v2.CopilotForBusinessTrialUpgraded",
      )
    end
  end

  context "copilot_business_trial_extended" do
    test "publishes to hydro" do
      Timecop.freeze do
        business_trial = create(:copilot_business_trial, :organization, :active)
        staff_actor = create(:user)

        additional_duration = 100

        business_trial.trial_length = business_trial.trial_length + additional_duration
        business_trial.save!

        # Now extend it
        Copilot::Instrumenter.instrument_copilot_business_trial_extended(
          staff_actor,
          business_trial,
          0,
          business_trial.trial_length,
        )

        assert_hydro_published(
          {
            staff_actor: Hydro::EntitySerializer.user(staff_actor),
            organization: Hydro::EntitySerializer.organization(business_trial.trialable),
            business: Hydro::EntitySerializer.business(business_trial.trialable.business),
            seat_count: 0,
            trial_duration_days: business_trial.trial_length,
            copilot_plan: Hydro::EntitySerializer.copilot_plan(business_trial.copilot_plan),
          },
          schema: "github.copilot.v2.CopilotForBusinessTrialExtended",
        )
      end
    end
  end

  context "copilot_business_trial_changed" do
    test "publishes to hydro" do
      Timecop.freeze do
        organization = create(:copilot_for_business_enabled_organization)
        business_trial = create(:copilot_business_trial, :organization, trialable: organization)
        staff_actor = create(:user)
        reason = "Trial converted to enterprise plan"
        previous_ends_at = business_trial.ends_at - 5.days
        previous_copilot_plan = "business"

        Copilot::Instrumenter.instrument_copilot_business_trial_changed(
          staff_actor,
          business_trial,
          reason,
          previous_ends_at,
          previous_copilot_plan,
        )

        assert_hydro_published(
          {
            staff_actor: Hydro::EntitySerializer.user(staff_actor),
            organization: Hydro::EntitySerializer.organization(organization),
            business: Hydro::EntitySerializer.business(organization.business),
            previous_trial_ends_at: Google::Protobuf::Timestamp.new(seconds: previous_ends_at.to_i, nanos: 0),
            updated_trial_ends_at: Google::Protobuf::Timestamp.new(seconds: business_trial.ends_at.to_i, nanos: 0),
            reason: reason,
            old_copilot_plan: Hydro::EntitySerializer.copilot_plan(previous_copilot_plan),
            new_copilot_plan: Hydro::EntitySerializer.copilot_plan(business_trial.copilot_plan),
          },
          schema: "github.copilot.v2.CopilotForBusinessTrialChanged"
        )
      end
    end
  end

  context "instrument_content_exclusion_changed" do
    test "publishes to audit log when an org level ignore config is changed" do
      organization = create(:copilot_for_business_enabled_organization)
      config = create(:copilot_content_exclusion_configuration, :organization, resource: organization)
      actor = organization.admins.first
      document = config.document

      event = ::Copilot::Events::COPILOT_FOR_BUSINESS_CONTENT_EXCLUSION_CHANGED
      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_content_exclusion_changed(
          organization,
          actor,
          document
        )
      end

      assert_subset_hash(
        {
          organization: organization.display_login,
          actor: actor.display_login,
          actor_id: actor.id,
          owner_type: "Organization",
          excluded_paths: document,
          action: "copilot.content_exclusion_changed"
        },
        events.first
      )
    end

    test "publishes to audit log when an repo level ignore config is changed" do
      organization = create(:copilot_for_business_enabled_organization)
      repository = create(:repository, owner: organization)
      config = create(:copilot_content_exclusion_configuration, :repository, resource: repository)
      actor = organization.admins.first
      document = config.document

      event = ::Copilot::Events::COPILOT_FOR_BUSINESS_CONTENT_EXCLUSION_CHANGED
      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_content_exclusion_changed(
          repository,
          actor,
          document,
        )
      end

      assert_subset_hash(
        {
          org: repository.owner.display_login,
          actor: actor.display_login,
          actor_id: actor.id,
          owner_type: "Repository",
          excluded_paths: document,
          repo: "#{organization.display_login}/#{repository.name}",
          repo_id: repository.id,
          action: "copilot.content_exclusion_changed"
        },
        events.first
      )
    end
  end

  context "#instrument_copilot_plan_destroyed" do
    test "publishes event when an organization's copilot plan is revoked" do
      organization = create(:copilot_for_business_enabled_organization)
      event = ::Copilot::Events::COPILOT_ACCESS_REVOKED

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_copilot_access_revoked(
          organization,
          T.must(::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable])
        )
      end

      assert_subset_hash(
        {
          org: organization.display_login,
          org_id: organization.id,
          reason: ::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable],
          action: ::Copilot::Events::COPILOT_ACCESS_REVOKED
        },
        events.first
      )
    end

    test "publishes an event when a business's copilot plan is revoked" do
      organization = create(:copilot_for_business_enabled_organization)
      business = organization.business
      event = ::Copilot::Events::COPILOT_ACCESS_REVOKED

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_copilot_access_revoked(
          organization.business,
          T.must(::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable])
        )
      end

      assert_subset_hash(
        {
          business: business.slug,
          business_id: business.id,
          reason: ::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable],
          action: ::Copilot::Events::COPILOT_ACCESS_REVOKED
        },
        events.first
      )

      assert_hydro_published(
        {
          owner_details: Hydro::EntitySerializer.copilot_owner_details(business),
          copilot_plan: "business",
          reason: ::Copilot::COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable],
        },
        schema: "github.copilot.v2.CopilotAccessRevoked",
      )
    end
  end

  test "#instrument_copilot_user_access_reinstated" do
    freeze_time do
      seat_assignment = create(:copilot_seat_assignment, :user, access_revoked_at: nil)
      reason = :just_because
      event = ::Copilot::Events::COPILOT_USER_ACCESS_REINSTATED

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_copilot_user_access_reinstated(
          seat_assignment,
          reason,
          { spaghetti: "western" }
        )
      end

      assert_subset_hash(
        {
          reason: reason,
          action: ::Copilot::Events::COPILOT_USER_ACCESS_REINSTATED,
          user_id: seat_assignment.assignable.id,
          assignment_id: seat_assignment.id,
          seat_assignment: seat_assignment.audit_log_payload,
          org_id: seat_assignment.owner.id,
          owner_type: "organization",
          actor: nil,
          actor_id: nil
        },
        events.first
      )

      assert_hydro_published(
        {
          reason: reason,
          seat_assignment: Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment),
          owner_details: Hydro::EntitySerializer.copilot_owner_details(seat_assignment.owner),
          copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western" }),
        },
        schema: "github.copilot.v2.CopilotUserAccessReinstated",
      )
    end
  end

  test "#instrument_copilot_user_access_revoked" do
    freeze_time do
      seat_assignment = create(:copilot_seat_assignment, :user, access_revoked_at: 1.day.ago.utc)
      reason = :just_because
      event = ::Copilot::Events::COPILOT_USER_ACCESS_REVOKED

      events = assert_performed_audit_entries(count: 1, only: event) do
        Copilot::Instrumenter.instrument_copilot_user_access_revoked(
          seat_assignment,
          reason,
          { spaghetti: "western" }
        )
      end

      assert_subset_hash(
        {
          reason: reason,
          action: ::Copilot::Events::COPILOT_USER_ACCESS_REVOKED,
          user_id: seat_assignment.assignable.id,
          assignment_id: seat_assignment.id,
          seat_assignment: seat_assignment.audit_log_payload,
          org_id: seat_assignment.owner.id,
          owner_type: "organization",
          actor: nil,
          actor_id: nil
        },
        events.first
      )

      assert_hydro_published(
        {
          reason: reason,
          seat_assignment: Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment),
          owner_details: Hydro::EntitySerializer.copilot_owner_details(seat_assignment.owner),
          copilot_for_business_details: Hydro::EntitySerializer.copilot_for_business_details({ spaghetti: "western" }),
        },
        schema: "github.copilot.v2.CopilotUserAccessRevoked",
      )
    end
  end
end if GitHub.copilot_enabled?
