# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessSuspensionDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @member_org_one = create :organization
    @member_org_two = create :organization
    @business = create :business, organizations: [@member_org_one, @member_org_two]
    @staffer = create(:staff_admin_user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  context "#suspended?" do
    test "returns true when marked as suspended" do
      @business.update_attribute(:suspended_at, Time.now)
      assert_predicate @business, :suspended?
    end

    test "returns false when not marked as suspended" do
      @business.update_attribute(:suspended_at, nil)
      refute_predicate @business, :suspended?
    end
  end

  context "#suspendable?" do
    test "returns true for a Business that is not staff owned", skip_enterprise: true do
      assert_predicate @business, :suspendable?
    end

    test "returns false for a Business that is staff owned", skip_enterprise: true do
      @business.update(staff_owned: true)

      refute_predicate @business, :suspendable?
    end

    test "returns false if running GHES", enterprise_only: true do
      refute_predicate @business, :suspendable?
    end
  end

  context "#suspend" do
    test "marks a Business as suspended" do
      @business.suspend("Offensive enterprise name")
      assert_predicate @business, :suspended?
    end

    test "does not mark a Business as suspended if they are listed as hammy" do
      refute_predicate @business, :hammy?

      @business.mark_as_hammy
      assert_predicate @business, :hammy?

      @business.suspend("Offensive enterprise name")
      refute_predicate @business, :suspended?
      assert_equal 0, GitHub.dogstats.increments("business.suspend").length
    end

    test "suspends all Organizations in a suspended Business" do
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.suspend("Offensive enterprise name")
      end

      assert_predicate @business, :suspended?
      assert_predicate @member_org_one.reload, :suspended?
      assert_predicate @member_org_two.reload, :suspended?
    end

    test "does SDN suspension on all Organizations in a suspended Business" do
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.sdn_suspend(staff_user: @staffer, reason: "Offensive enterprise name")
      end

      assert_predicate @business, :suspended?
      assert_predicate @member_org_one.reload, :sdn_suspended?
      assert_predicate @member_org_two.reload, :sdn_suspended?
    end

    test "does not suspend all Organizations if reason is nil during enterprise suspension" do
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        assert_raises_with_message(ArgumentError, "wrong number of arguments (given 0, expected 1)") do
          @business.suspend
        end
      end

      refute_predicate @business, :suspended?
      refute_predicate @member_org_one.reload, :suspended?
      refute_predicate @member_org_two.reload, :suspended?
    end

    test "does not do SDN suspension on all Organizations if reason is nil during enterprise suspension" do
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        assert_raises_with_message(ArgumentError, "missing keyword: :reason") do
          @business.sdn_suspend(staff_user: @staffer)
        end
      end

      refute_predicate @business, :suspended?
      refute_predicate @member_org_one.reload, :sdn_suspended?
      refute_predicate @member_org_two.reload, :sdn_suspended?
    end

    test "instruments business.suspend audit log event" do
      events = subscribe "business.suspend"
      reason = "Offensive enterprise name"
      @business.suspend(reason, actor: @staffer)

      expected_payload = {
        business: @business.slug,
        business_id: @business.id,
        name: @business.slug,
        reason: reason,
        staff_actor: @staffer.login,
        staff_actor_id: @staffer.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id
      }

      assert event = events.pop, "a business.suspend event was expected"
      assert_equal "business.suspend", event.name
      assert_equal event.payload.merge(expected_payload), event.payload
      assert_equal 1, GitHub.dogstats.increments("business.suspend").length
    end

    test "instruments org.suspend audit log event on a suspended business' member orgs" do
      events = subscribe "org.suspend"
      reason = "Offensive enterprise name"
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.suspend("Offensive enterprise name", actor: @staffer)
      end

      expected_payload_1 = {
        org: @member_org_one.login,
        org_id: @member_org_one.id,
        reason: "The owning #{@business.name} enterprise was suspended: " + reason,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id
      }

      expected_payload_2 = {
        org: @member_org_two.login,
        org_id: @member_org_two.id,
        reason: "The owning #{@business.name} enterprise was suspended: " + reason,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id
      }

      assert actual_events = [events.pop, events.pop], "2 org.suspend events were expected"

      event = actual_events.find { |e| e.payload[:org] == @member_org_one.login }
      assert_equal "org.suspend", event.name
      assert_equal event.payload.merge(expected_payload_1), event.payload

      event = actual_events.find { |e| e.payload[:org] == @member_org_two.login }
      assert_equal "org.suspend", event.name
      assert_equal event.payload.merge(expected_payload_2), event.payload
    end

    test "publishes an abuse classification Hydro event for suspension" do
      now = Time.parse("2018-01-01")

      Timecop.freeze(now) do
        analyst = create :user, login: "triage-worker"

        @business.suspend("Offensive enterprise name", actor: analyst)

        message = {
          request_context: nil,
          actor: Hydro::EntitySerializer.user(analyst),
          business: Hydro::EntitySerializer.business(@business),
          previous_classification: :NONE,
          current_classification: :NONE,
          previous_spammy_reason: { value: "" },
          current_spammy_reason: { value: "" },
          previously_suspended: { value: false },
          currently_suspended: { value: true },
          currently_deleted: { value: false },
          origin: :DOTCOM,
          queue_action: :QUEUE_ACTION_NONE,
          queue_entry: nil,
          previous_queue: nil,
          current_queue: nil,
          queued_time_in_seconds: nil,
        }

        assert_hydro_published message, schema: "github.v1.EnterpriseAbuseClassification"
        assert_hydro_messages count: 1, schema: "github.v1.EnterpriseAbuseClassification"
      end
    end

    if GitHub.billing_enabled?
      test "cancels all external subscriptions for the suspended Business" do
        staff = create :staff_admin_user
        @business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)

        @business.enable_automatic_self_serve_payment(staff)
        assert_predicate @business, :automatic_self_serve_payment_enabled?

        plan_subscription = create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_enqueued_jobs(1, only: CloseOutZuoraSubscriptionJob) do
          @business.suspend("Offensive enterprise name")
        end
        # Ensure auto-pay isn't changed
        assert_predicate @business.reload, :automatic_self_serve_payment_enabled?
      end

      test "disables advanced security for a suspended self-serve Business" do
        create(:billing_product_uuid, :advanced_security)
        staff = create :staff_admin_user

        @business.subscribe_to_advanced_security(seats: 100, actor: staff, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month, is_stafftools_action: true)
        @business.customer.update(billing_type: Customer::BILLING_TYPE_CARD)

        @business.enable_automatic_self_serve_payment(staff)
        assert_predicate @business, :automatic_self_serve_payment_enabled?
        assert @business.advanced_security_purchased_for_entity?

        plan_subscription = create(:billing_plan_subscription, :zuora, customer: @business.customer)

        assert_enqueued_jobs(1, only: CloseOutZuoraSubscriptionJob) do
          @business.suspend("Offensive enterprise name")
        end
        # Ensure auto-pay isn't changed
        assert_predicate @business.reload, :automatic_self_serve_payment_enabled?

        refute @business.advanced_security_purchased_for_entity?
        assert_equal @business.advanced_security_seats_for_entity, 0 # NOTE: Currently 0 means unlimited seats when in trial mode
      end
    end
  end

  context "#unsuspend" do
    test "marks a Business as not suspended" do
      @business.suspend("Offensive enterprise name")
      assert_predicate @business, :suspended?

      @business.unsuspend("Nevermind its ok")
      refute_predicate @business, :suspended?
    end

    test "unsuspends all Organizations in a unsuspended Business" do
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.suspend("Offensive enterprise name")
      end

      assert_predicate @business, :suspended?
      assert_predicate @member_org_one.reload, :suspended?
      assert_predicate @member_org_two.reload, :suspended?

      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.unsuspend("Nevermind its ok")
      end

      refute_predicate @business, :suspended?
      refute_predicate @member_org_one.reload, :suspended?
      refute_predicate @member_org_two.reload, :suspended?
    end

    test "does SDN unsuspension on all Organizations in a unsuspended Business" do
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.sdn_suspend(staff_user: @staffer, reason: "Offensive enterprise name")
      end

      assert_predicate @business, :suspended?
      assert_predicate @member_org_one.reload, :sdn_suspended?
      assert_predicate @member_org_two.reload, :sdn_suspended?

      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.sdn_unsuspend(staff_user: @staffer, reason: "Not offensive enterprise name")

      end

      refute_predicate @business, :suspended?
      refute_predicate @member_org_one.reload, :sdn_suspended?
      refute_predicate @member_org_two.reload, :sdn_suspended?
    end

    test "does not unsuspend all Organizations if reason is nil during enterprise unsuspension" do
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.suspend("Offensive enterprise name")
      end

      assert_predicate @business, :suspended?
      assert_predicate @member_org_one.reload, :suspended?
      assert_predicate @member_org_two.reload, :suspended?

      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        assert_raises_with_message(ArgumentError, "wrong number of arguments (given 0, expected 1)") do
          @business.unsuspend
        end
      end

      assert_predicate @business, :suspended?
      assert_predicate @member_org_one.reload, :suspended?
      assert_predicate @member_org_two.reload, :suspended?
    end

    test "does not do SDN unsuspension on all Organizations if reason is nil during enterprise unsuspension" do
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.sdn_suspend(staff_user: @staffer, reason: "Offensive enterprise name")

      end

      assert_predicate @business, :suspended?
      assert_predicate @member_org_one.reload, :sdn_suspended?
      assert_predicate @member_org_two.reload, :sdn_suspended?

      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        assert_raises_with_message(ArgumentError, "missing keyword: :reason") do
          @business.sdn_unsuspend(staff_user: @staffer)
        end
      end

      assert_predicate @business, :suspended?
      assert_predicate @member_org_one.reload, :sdn_suspended?
      assert_predicate @member_org_two.reload, :sdn_suspended?
    end

    test "instruments business.unsuspend audit log event" do
      old_reason = "Offensive enterprise name"
      @business.suspend(old_reason)
      assert_predicate @business, :suspended?

      events = subscribe "business.unsuspend"
      reason = "Nevermind"
      @business.unsuspend(reason, actor: @staffer)

      expected_payload = {
        business: @business.slug,
        business_id: @business.id,
        name: @business.slug,
        reason: reason,
        staff_actor: @staffer.login,
        staff_actor_id: @staffer.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id
      }

      assert event = events.pop, "a business.unsuspend event was expected"
      assert_equal "business.unsuspend", event.name
      assert_equal event.payload.merge(expected_payload), event.payload
      assert_equal 1, GitHub.dogstats.increments("business.unsuspend").length
    end

    test "instruments org.unsuspend audit log event on an unsuspended business' member orgs" do
      old_reason = "Offensive enterprise name"
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.suspend(old_reason)
      end
      assert_predicate @business, :suspended?

      events = subscribe "org.unsuspend"
      reason = "Nevermind"
      perform_enqueued_jobs only: ToggleSuspensionStatusOnBusinessOrganizationsJob do
        @business.unsuspend(reason, actor: @staffer)
      end

      expected_payload_1 = {
        org: @member_org_one.login,
        org_id: @member_org_one.id,
        reason: "The owning #{@business.name} enterprise was unsuspended: " + reason,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id
      }

      expected_payload_2 = {
        org: @member_org_two.login,
        org_id: @member_org_two.id,
        reason: "The owning #{@business.name} enterprise was unsuspended: " + reason,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id
      }

      assert actual_events = [events.pop, events.pop], "2 org.unsuspend events were expected"

      event = actual_events.find { |e| e.payload[:org] == @member_org_one.login }
      assert_equal "org.unsuspend", event.name
      assert_equal event.payload.merge(expected_payload_1), event.payload

      event = actual_events.find { |e| e.payload[:org] == @member_org_two.login }
      assert_equal "org.unsuspend", event.name
      assert_equal event.payload.merge(expected_payload_2), event.payload
    end

    test "publishes an abuse classification Hydro event for unsuspension" do
      now = Time.parse("2018-01-01")

      Timecop.freeze(now) do
        analyst = create :user, login: "triage-worker"

        @business.suspend("Offensive enterprise name", actor: analyst)
        assert_predicate @business, :suspended?

        @business.unsuspend("Nevermind its ok", actor: analyst)

        message = {
          request_context: nil,
          actor: Hydro::EntitySerializer.user(analyst),
          business: Hydro::EntitySerializer.business(@business),
          previous_classification: :NONE,
          current_classification: :NONE,
          previous_spammy_reason: { value: "" },
          current_spammy_reason: { value: "" },
          previously_suspended: { value: true },
          currently_suspended: { value: false },
          currently_deleted: { value: false },
          origin: :DOTCOM,
          queue_action: :QUEUE_ACTION_NONE,
          queue_entry: nil,
          previous_queue: nil,
          current_queue: nil,
          queued_time_in_seconds: nil,
        }

        assert_hydro_published message, schema: "github.v1.EnterpriseAbuseClassification"
        assert_hydro_messages count: 2, schema: "github.v1.EnterpriseAbuseClassification"
      end
    end

    if GitHub.billing_enabled?
      test "recreates all external subscriptions for the Business" do
        plan_subscription = create(:billing_plan_subscription, customer: @business.customer)

        @business.suspend("Offensive enterprise name")

        assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
          @business.unsuspend("Nevermind its ok")
        end
      end
    end
  end
end unless GitHub.enterprise?
