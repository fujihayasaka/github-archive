# typed: strict
# frozen_string_literal: true

require "test_helper"

module OwningEntityHelpers
  include FactoryBot::Syntax::Methods


  sig { returns(::Organization) }
  def zuora_organization
    admin = create(:user)
    invoiced_org = create(:invoiced_org, plan: GitHub::Plan.business, admins: [admin])
    invoiced_org.customer.update!(zuora_account_id: SecureRandom.hex)
    create(
      :billing_plan_subscription,
      :zuora,
      user: invoiced_org,
      customer: invoiced_org.customer,
    )
    invoiced_org
  end

  sig { returns(::Organization) }
  def azure_organization
    admin = create(:user)
    org = create(:organization, :with_azure_subscription, admins: [admin], customer: azure_customer)
    org.reload
    org
  end

  sig { returns(::Business) }
  def zuora_business
    create(:business)
  end

  sig { returns(::Business) }
  def azure_business
    biz = create(:business, :with_azure_subscription, customer: azure_customer)
    biz.reload
    biz
  end

  sig { returns(::Customer) }
  def azure_customer
    customer = create(:customer, metered_via_azure: true, azure_subscription_id: SecureRandom.uuid)
    create(:billing_sales_serve_plan_subscription, customer: customer)
    customer
  end

  # Returns a business with two enterprise teams, each with a Copilot SeatAssignment, and 4 Copilot seats
  # The two enterprise teams each have one unique user and one user that is a member of both enterprise teams.
  sig { returns(::Business) }
  def copilot_non_emu_basic_business
    basic_enterprise = create(:business, :default_managed, :with_azure_subscription, seats_plan_type: :basic, customer: azure_customer)

    ent_team1 = create(:enterprise_team, name: "ent-team-1", business: basic_enterprise)
    ent_team2 = create(:enterprise_team, name: "ent-team-2", business: basic_enterprise)

    duped_user = create(:user)
    basic_enterprise.add_user_accounts([duped_user.id], business_roles_bitfield: 0)

    [ent_team1, ent_team2].each do |ent_team|
      other_user = create(:user)
      basic_enterprise.add_user_accounts([other_user.id], business_roles_bitfield: 0)
      ent_team.enterprise_team_memberships.create!(user_id: other_user.id)
      ent_team.enterprise_team_memberships.create!(user_id: duped_user.id)

      seat_assignment = create(:copilot_seat_assignment,
        :enterprise_team,
        supplied_business: basic_enterprise,
        assignable: ent_team,
      )

      # Intentionally _NOT_ using .convert_to_seats as that de-dupes users across enterprise teams
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: other_user)
      create(:copilot_seat, seat_assignment: seat_assignment, assigned_user: duped_user)
    end

    basic_enterprise.reload
    basic_enterprise
  end
end

class Copilot::Billing::CancellationTelemetryTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include OwningEntityHelpers

  setup do
    GitHub.flipper[:copilot_immediate_cancellation_telemetry].enable
  end

  context "#payment_submission_target" do
    test "returns zuora for an organization unaffiliated with a business" do
      owner = zuora_organization
      emittable = Copilot::Billing::CancellationTelemetry.new(owner)

      assert_equal "zuora", emittable.payment_submission_target
    end

    test "returns zuora for a business invoiced with zuora" do
      owner = zuora_business
      emittable = Copilot::Billing::CancellationTelemetry.new(owner)

      assert_equal "zuora", emittable.payment_submission_target
    end

    test "returns azure for a business metered via with azure" do
      owner = azure_business
      emittable = Copilot::Billing::CancellationTelemetry.new(owner)

      assert_equal "azure", emittable.payment_submission_target
    end

    test "returns unknown and logs otherwise" do
      customer = create(:customer, :invoiced)
      owner = create(:business, customer: customer)
      logs = capture_logs do
        emittable = Copilot::Billing::CancellationTelemetry.new(owner)

        assert_equal "unknown", emittable.payment_submission_target
      end

      assert_match /Unable to determine payment_submission_target for billable owner/, logs
      assert_includes logs, "gh.copilot.owner.id=\"#{owner.id}\""
      assert_includes logs, "gh.copilot.owner.type=\"Business\""
      assert_includes logs, "gh.code.namespace=\"Copilot::Billing::CancellationTelemetry\""
    end
  end

  context "#seat_cancellation_data" do
    test "returns zeroed out data by default" do
      [
        { entity: zuora_business, target: "zuora" },
        { entity: azure_business, target: "azure" },
        { entity: zuora_organization, target: "zuora" },
        { entity: azure_organization, target: "azure", },
        { entity: copilot_non_emu_basic_business, target: "azure" }
      ].each do |test_case|
        emittable = Copilot::Billing::CancellationTelemetry.new(test_case[:entity])
        submission_target = test_case[:target]

        assert_equal submission_target, emittable.seat_cancellation_data[:payment_submission_target]
        assert_equal 0, emittable.seat_cancellation_data[:num_pending_cancelled_seats]
        assert_equal 0, emittable.seat_cancellation_data[:num_new_pending_cancelled_seats]
        assert_equal 0, emittable.seat_cancellation_data[:num_immediately_cancelled_seats]
      end
    end
  end

  context "#num_pending_cancelled_seats" do
    context "for standalone organizations" do
      test "counts the total number of seats pending cancellation for the billing cycle" do
        org = zuora_organization


        travel_to(org.current_metered_billing_cycle_starts_at) do
          # Create a few seat assignments and a seat per assignment
          3.times do
            user = create(:user)
            org.add_member(user)
            assignment = create(:copilot_seat_assignment, assignable: user, owner: org, assigning_user: org.admins.first)
            assignment.convert_to_seats
            assignment.update(pending_cancellation_date: org.next_metered_billing_cycle_starts_at)
          end
        end

        # Add one user with an old pending cancellation. Shouldn't happen, but it does
        travel_to((org.current_metered_billing_cycle_starts_at - 30)) do
          user = create(:user)
          org.add_member(user)
          assignment = create(:copilot_seat_assignment, assignable: user, owner: org, assigning_user: org.admins.first)
          assignment.convert_to_seats
          assignment.update(pending_cancellation_date: org.current_metered_billing_cycle_starts_at - 30)
        end

        travel_to(org.current_metered_billing_cycle_starts_at) do
          telemetry = Copilot::Billing::CancellationTelemetry.new(org)
          assert_equal 3, telemetry.num_pending_cancelled_seats
        end
      end
    end

    context "for organizations with a parent business" do
      test "counts the total number of seats pending cancellation for the billing cycle" do
        biz = zuora_business

        org_a = create(:organization, business: biz)
        org_b = create(:organization, business: biz)
        org_c  = create(:organization, business: biz)

        shared_user_a = create(:user)
        user_b = create(:user)
        user_c = create(:user)
        user_d = create(:user)

        org_a.add_member(shared_user_a)
        org_a.add_member(user_b)
        org_b.add_member(shared_user_a)
        org_b.add_member(user_c)
        [user_d, shared_user_a].each { |u| org_c.add_member(u) }

        copilot_biz = Copilot::Business.new(biz)
        copilot_biz.enable_copilot!
        copilot_biz.enable_copilot_for_all_organizations!

        user_a_assignment = create(:copilot_seat_assignment, assignable: shared_user_a, owner: org_a, assigning_user: org_a.admins.first)
        user_a_assignment.convert_to_seats
        user_a_assignment.update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)

        user_a_assignment = create(:copilot_seat_assignment, assignable: shared_user_a, owner: org_b, assigning_user: org_b.admins.first)
        user_a_assignment.convert_to_seats

        org_c_assignment = create(:copilot_seat_assignment, assignable: org_c, owner: org_c, assigning_user: org_c.admins.first)
        org_c_assignment.convert_to_seats
        org_c_assignment.update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)

        [user_b, user_c, user_d].each do |user|
          owner = user.organizations.first
          admin = owner.admins.first
          assignment = create(:copilot_seat_assignment, assignable: user, owner: owner, assigning_user: admin)
          assignment.convert_to_seats
        end

        users_with_at_least_one_active_seat =
          Set.new(
            Copilot::Seat
              .multi_org_users_with_active_seat(
                owner_ids: biz.organizations.map(&:id),
                user_ids: [shared_user_a.id]
              )
              .map(&:assigned_user_id)
          )
        emittable = Copilot::Billing::CancellationTelemetry.new(org_a, users_with_at_least_one_active_seat)
        # we expect no pending cancellations for the user in org_a, as they have an active seat in org_b
        assert_equal 0, emittable.num_pending_cancelled_seats
      end
    end

    context "for standalone business" do
      test "counts the total number of seats pending cancellation for the billing cycle" do
        biz = copilot_non_emu_basic_business
        assignments = Copilot::SeatAssignment.for_standalone_business(biz)
        T.must(assignments.first).update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)
        T.must(assignments.last).update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)

        emittable = Copilot::Billing::CancellationTelemetry.new(biz)
        assert_equal 3, emittable.num_pending_cancelled_seats
      end
    end
  end

  context "#num_new_pending_cancelled_seats" do
    context "for standalone organizations" do
      test "returns the total number of seats cancelled since the beginning of the day" do
        org = zuora_organization

        # Create a few seat assignments and a seat per assignment
        3.times do
          user = create(:user)
          org.add_member(user)
          assignment = create(:copilot_seat_assignment, assignable: user, owner: org, assigning_user: org.admins.first)
          assignment.convert_to_seats
        end

        assignments = Copilot::SeatAssignment.for_organization(org)

        moment = 3.days.ago.to_time
        travel_to moment do
          assignments.first!.update(pending_cancellation_date: org.next_metered_billing_cycle_starts_at)
        end

        assignments.last!.update(pending_cancellation_date: org.next_metered_billing_cycle_starts_at)

        emittable = Copilot::Billing::CancellationTelemetry.new(org)

        assert_equal 1, emittable.num_new_pending_cancelled_seats
      end
    end

    context "for organizations with a parent business" do
      test "returns total number of seats cancelled since the beginning of the day" do
        biz = zuora_business

        org_a = create(:organization, business: biz)
        org_b = create(:organization, business: biz)

        shared_user_a = create(:user)
        user_b = create(:user)
        user_c = create(:user)

        org_a.add_member(shared_user_a)
        org_a.add_member(user_b)
        org_b.add_member(shared_user_a)
        org_b.add_member(user_c)

        copilot_biz = Copilot::Business.new(biz)
        copilot_biz.enable_copilot!
        copilot_biz.enable_copilot_for_all_organizations!

        user_a_cancelled_assignment = create(:copilot_seat_assignment, assignable: shared_user_a, owner: org_a, assigning_user: org_a.admins.first)
        user_a_cancelled_assignment.convert_to_seats
        user_a_cancelled_assignment.update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)

        user_a_assignment = create(:copilot_seat_assignment, assignable: shared_user_a, owner: org_b, assigning_user: org_b.admins.first)
        user_a_assignment.convert_to_seats

        [user_b, user_c,].each do |user|
          owner = user.organizations.first
          admin = owner.admins.first
          assignment = create(:copilot_seat_assignment, assignable: user, owner: owner, assigning_user: admin)
          assignment.convert_to_seats
        end

        Copilot::SeatAssignment.find_by(assignable: user_c)&.update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)

        users_with_at_least_one_active_seat =
          Set.new(
            Copilot::Seat
              .multi_org_users_with_active_seat(
                owner_ids: biz.organizations.map(&:id),
                user_ids: [shared_user_a.id]
              )
              .map(&:assigned_user_id)
          )

        cancellation_telemetry = Copilot::Billing::CancellationTelemetry
          .new(org_a, users_with_at_least_one_active_seat)

        assert_equal 0, cancellation_telemetry.num_new_pending_cancelled_seats

        # travel back in time and cancel the other seat assignment, we should now show 1 new pending cancelled seat,
        # as there user has no more active seats and today's cancellation reflects a drop in ARR
        moment = 3.days.ago.to_time
        travel_to moment do
          user_a_assignment.update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)
        end

        users_with_at_least_one_active_seat =
          Set.new(
            Copilot::Seat
              .multi_org_users_with_active_seat(
                owner_ids: biz.organizations.map(&:id),
                user_ids: [shared_user_a.id]
              )
              .map(&:assigned_user_id)
          )

        cancellation_telemetry = Copilot::Billing::CancellationTelemetry
          .new(org_a, users_with_at_least_one_active_seat)

        assert_equal 1, cancellation_telemetry.num_new_pending_cancelled_seats
      end

      test "returns correct number of newly pending cancelled seats when all of them are cancelled on the same day" do
        biz = zuora_business

        org_a = create(:organization, business: biz)
        org_b = create(:organization, business: biz)

        shared_user_a = create(:user)

        org_a.add_member(shared_user_a)
        org_b.add_member(shared_user_a)

        copilot_biz = Copilot::Business.new(biz)
        copilot_biz.enable_copilot!
        copilot_biz.enable_copilot_for_all_organizations!

        user_a_cancelled_assignment = create(:copilot_seat_assignment, assignable: shared_user_a, owner: org_a, assigning_user: org_a.admins.first)
        user_a_cancelled_assignment.convert_to_seats
        user_a_cancelled_assignment.update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)

        user_a_assignment = create(:copilot_seat_assignment, assignable: shared_user_a, owner: org_b, assigning_user: org_b.admins.first)
        user_a_assignment.convert_to_seats
        user_a_assignment.update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)


        users_with_at_least_one_active_seat =
          Set.new(
            Copilot::Seat
              .multi_org_users_with_active_seat(
                owner_ids: biz.organizations.map(&:id),
                user_ids: [shared_user_a.id]
              )
              .map(&:assigned_user_id)
          )

        cancellation_telemetry = Copilot::Billing::CancellationTelemetry
          .new(org_a, users_with_at_least_one_active_seat)

        assert_equal 1, cancellation_telemetry.num_new_pending_cancelled_seats
      end
    end

    context "for standalone business" do
      test "returns the total number of seats cancelled since the beginning of the day"  do
        biz = copilot_non_emu_basic_business
        assignments = Copilot::SeatAssignment.for_standalone_business(biz)

        moment = 3.days.ago.to_time

        travel_to moment do
          T.must(assignments.first).update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)
        end
        T.must(assignments.last).update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)

        emittable = Copilot::Billing::CancellationTelemetry.new(biz)
        assert_equal 2, emittable.num_new_pending_cancelled_seats
      end

      test "returns correct number of cancelled seats when a user has at least one other active seat in multiple enterprise teams" do
        biz = copilot_non_emu_basic_business
        assignments = Copilot::SeatAssignment.for_standalone_business(biz)
        T.must(assignments.last).update(pending_cancellation_date: biz.next_metered_billing_cycle_starts_at)

        emittable = Copilot::Billing::CancellationTelemetry.new(biz)
        assert_equal 1, emittable.num_new_pending_cancelled_seats
      end
    end
  end

  context "#num_immediately_cancelled_seats" do
    test "returns 0 when feature flag is disabled" do
      GitHub.flipper[:copilot_immediate_cancellation_telemetry].disable

      biz = copilot_non_emu_basic_business
      assignments = Copilot::SeatAssignment.for_standalone_business(biz)
      assignment = T.must(assignments.last)

      # sanity check
      assert_equal 2, assignment.seats.count

      assignment.seats.destroy_all
      assignment.destroy

      emittable = Copilot::Billing::CancellationTelemetry.new(biz)
      # There is one shared user between assignments, only a single seat was truly deleted.
      assert_equal 0, emittable.num_immediately_cancelled_seats
    end

    context "for a standalone business" do
      test "only counts seats that were cancelled today when user doesn't have any active seats" do
        biz = copilot_non_emu_basic_business
        assignments = Copilot::SeatAssignment.for_standalone_business(biz)
        assignment = T.must(assignments.last)

        # sanity check
        assert_equal 2, assignment.seats.count

        assignment.seats.destroy_all
        assignment.destroy

        emittable = Copilot::Billing::CancellationTelemetry.new(biz)
        # There is one shared user between assignments, only a single seat was truly deleted.
        assert_equal 1, emittable.num_immediately_cancelled_seats
      end
    end

    context "for standalone organizations" do
      test "counts all seats deleted today" do
        org = zuora_organization

        # Create a few seat assignments and a seat per assignment
        2.times do
          user = create(:user)
          org.add_member(user)
          assignment = create(:copilot_seat_assignment, assignable: user, owner: org, assigning_user: org.admins.first)
          assignment.convert_to_seats
        end

        assignments = Copilot::SeatAssignment.for_organization(org)
        T.must(assignments.first).update(pending_cancellation_date: org.next_metered_billing_cycle_starts_at)
        T.must(assignments.last).seats.destroy_all
        T.must(assignments.last).destroy

        emittable = Copilot::Billing::CancellationTelemetry.new(org)

        assert_equal 1, emittable.num_immediately_cancelled_seats
      end
    end

    context "for an organization with a parent busines" do
      test "counts seats deleted today when user doesn't have any other active seats" do
        biz = zuora_business

        org_a = create(:organization, business: biz)
        org_b = create(:organization, business: biz)

        shared_user_a = create(:user)
        user_b = create(:user)
        user_c = create(:user)

        org_a.add_member(shared_user_a)
        org_a.add_member(user_b)
        org_b.add_member(shared_user_a)
        org_b.add_member(user_c)

        copilot_biz = Copilot::Business.new(biz)
        copilot_biz.enable_copilot!
        copilot_biz.enable_copilot_for_all_organizations!

        user_a_deleted_assignment = create(:copilot_seat_assignment, assignable: shared_user_a, owner: org_a, assigning_user: org_a.admins.first)
        user_a_deleted_assignment.convert_to_seats
        user_a_deleted_assignment.seats.destroy_all
        user_a_deleted_assignment.destroy

        user_a_assignment = create(:copilot_seat_assignment, assignable: shared_user_a, owner: org_b, assigning_user: org_b.admins.first)
        user_a_assignment.convert_to_seats

        [user_b, user_c,].each do |user|
          owner = user.organizations.first
          admin = owner.admins.first
          assignment = create(:copilot_seat_assignment, assignable: user, owner: owner, assigning_user: admin)
          assignment.convert_to_seats
        end

        emittable = Copilot::Billing::CancellationTelemetry.new(org_a, Set.new([shared_user_a.id]))
        assert_equal 0, emittable.num_immediately_cancelled_seats

        user_b_assignment = Copilot::SeatAssignment.find_by(assignable: user_b)
        user_b_assignment&.seats&.destroy_all
        user_b_assignment&.destroy

        emittable = Copilot::Billing::CancellationTelemetry.new(org_a, Set.new([shared_user_a.id]))
        assert_equal 1, emittable.num_immediately_cancelled_seats
      end
    end
  end
end unless TestEnv.test_with_all_emus? || GitHub.enterprise?
