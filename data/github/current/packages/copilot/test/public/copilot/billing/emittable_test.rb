# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Billing::EmittableTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "#number_of_days_in_billing_cycle" do
    test "returns 31.0 for 31 day billing cycle" do
      moment = GitHub::Billing.timezone.local(2018, 12, 20, 12, 12)
      travel_to moment do
        organization = create(:business_organization)
        assert_equal 31.0, Copilot::Billing::Emittable.new(organization).number_of_days_in_billing_cycle
      end
    end

    test "returns 30.0 for 30 day billing cycle" do
      moment = GitHub::Billing.timezone.local(2018, 4, 20, 12, 12)
      travel_to moment do
        organization = create(:business_organization)
        assert_equal 30.0, Copilot::Billing::Emittable.new(organization).number_of_days_in_billing_cycle
      end
    end

    test "returns 28.0 for 29 day billing cycle" do
      moment = GitHub::Billing.timezone.local(2018, 2, 20, 12, 12)
      travel_to moment do
        organization = create(:business_organization)
        assert_equal 28.0, Copilot::Billing::Emittable.new(organization).number_of_days_in_billing_cycle
      end
    end

    test "returns 29.0 for 28 day billing cycle" do
      moment = GitHub::Billing.timezone.local(2020, 2, 20, 12, 12)
      travel_to moment do
        organization = create(:business_organization)
        assert_equal 29.0, Copilot::Billing::Emittable.new(organization).number_of_days_in_billing_cycle
      end
    end
  end

  context "#seat_count" do
    test "returns 0 for 0 seat" do
      assert_equal 0.0, Copilot::Billing::Emittable.new(create(:business_organization)).seat_count
    end

    test "returns 1 for 1 seat" do
      seat = create(:copilot_seat)
      assert_equal 1.0, Copilot::Billing::Emittable.new(seat.organization).seat_count
    end

    test "returns only active seats for special organizations" do
      assert_equal 0, Copilot::Seat.count
      organization = create(:enterprise_linked_organization, id: Copilot::MS_COPILOT_ORG_ID)
      admin = organization.admin
      user = create(:user)
      other_user = create(:user)
      organization.add_member(user)
      organization.add_member(other_user)
      5.times do
        organization.add_member(create(:user))
      end
      assert_equal 8, organization.members.count
      organization.reload
      Copilot::Organization.new(organization).enable_copilot!
      assignment = Copilot::SeatAssignment.create!(
        organization: organization,
        owner_type: "Organization",
        owner_id: organization.id,
        assignable_type: "Organization",
        assignable_id: organization.id,
        assigning_user: admin,
      )
      assignment.save!
      assignment.convert_to_seats

      assert_equal Copilot::MS_COPILOT_ORG_ID, organization.id
      assert_equal assignment.owner_id, Copilot::MS_COPILOT_ORG_ID
      assert_equal assignment.organization_id, Copilot::MS_COPILOT_ORG_ID

      # let's make one of them active
      create(:copilot_aggregate_usage_detail, user: user)
      assert_equal 1.0, Copilot::Billing::Emittable.new(organization).seat_count

      # let's make another one active
      create(:copilot_aggregate_usage_detail, user: other_user)
      assert_equal 2.0, Copilot::Billing::Emittable.new(organization).seat_count
    end

    test "de-dupes across enterprise teams" do
      basic_enterprise = create(:business, :default_managed, seats_plan_type: :basic)

      ent_team1 = create(:enterprise_team, name: "ent-team-1", business: basic_enterprise)
      ent_team2 = create(:enterprise_team, name: "ent-team-2", business: basic_enterprise)

      duped_user = create(:user)
      basic_enterprise.add_user_accounts([duped_user.id], business_roles_bitfield: 0)

      assert_equal 0, Copilot::Seat.count

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

      assert_equal 4, Copilot::Seat.count

      # duped_user + other user from ent_team1 + other user from ent_team2
      assert_equal 3.0, Copilot::Billing::Emittable.new(basic_enterprise).seat_count
    end
  end

  context "#per_seat_rate" do
    test "returns 0.032258064 for 31 day billing cycle" do
      moment = GitHub::Billing.timezone.local(2018, 12, 20, 12, 12)
      travel_to moment do
        organization = create(:business_organization)
        assert_equal 0.032258064, Copilot::Billing::Emittable.new(organization).per_seat_rate
      end
    end

    test "returns 0.033333333 for 30 day billing cycle" do
      moment = GitHub::Billing.timezone.local(2018, 4, 20, 12, 12)
      travel_to moment do
        organization = create(:business_organization)
        assert_equal 0.033333333, Copilot::Billing::Emittable.new(organization).per_seat_rate
      end
    end

    test "returns 0.035714285 for 28 day billing cycle" do
      moment = GitHub::Billing.timezone.local(2018, 2, 20, 12, 12)
      travel_to moment do
        organization = create(:business_organization)
        assert_equal 0.035714285, Copilot::Billing::Emittable.new(organization).per_seat_rate
      end
    end

    test "returns 0.034482758 for 29 day billing cycle" do
      moment = GitHub::Billing.timezone.local(2020, 2, 20, 12, 12)
      travel_to moment do
        organization = create(:business_organization)
        assert_equal 0.034482758, Copilot::Billing::Emittable.new(organization).per_seat_rate
      end
    end
  end

  context "#meuse_emission_payload" do
    test "it has a proper meuse payload for an organization" do
      assignment = create(:copilot_seat_assignment, :organization)
      org = assignment.owner

      10.times do
        org.add_member(create(:user))
      end
      org.reload
      assignment.reload

      assert_equal 11, org.member_ids.count
      assert_equal 11, assignment.assignable_count
      assignment.convert_to_seats

      emittable = Copilot::Billing::Emittable.new(assignment.owner)

      assert_equal "copilot", emittable.meuse_emission_payload[:product_name]
      assert_equal "copilot_for_business", emittable.meuse_emission_payload[:product_sku_name]
      assert_equal assignment.owner.id, emittable.meuse_emission_payload[:account_id]
      assert_nil emittable.meuse_emission_payload[:customer_id]
      assert_equal GlobalID.create(assignment.owner).to_s, emittable.meuse_emission_payload[:source_uri]
      refute_equal 0.0, emittable.meuse_emission_payload[:quantity]
    end

    test "it has a proper meuse payload for an enterprise team enterprise/standalone" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      assignment.convert_to_seats

      emittable = Copilot::Billing::Emittable.new(assignment.owner)
      assert_equal "copilot", emittable.meuse_emission_payload[:product_name]
      assert_equal "copilot_standalone", emittable.meuse_emission_payload[:product_sku_name]
      assert_nil emittable.meuse_emission_payload[:account_id]
      assert_equal assignment.owner.customer_id, emittable.meuse_emission_payload[:customer_id]
      assert_equal GlobalID.create(assignment.owner).to_s, emittable.meuse_emission_payload[:source_uri]
      refute_equal 0.0, emittable.meuse_emission_payload[:quantity]
    end

    test "it has a proper meuse payload for an organization on the CE plan" do
      assignment = create(:copilot_seat_assignment, :organization)
      org = assignment.owner
      business = create(:business)
      business.add_organization(org)
      Copilot::Business.new(business).copilot_plan_enterprise!

      10.times do
        org.add_member(create(:user))
      end
      org.reload
      assignment.reload

      assert_equal 11, org.member_ids.count
      assert_equal 11, assignment.assignable_count
      assignment.convert_to_seats

      emittable = Copilot::Billing::Emittable.new(assignment.owner)

      assert_equal "copilot", emittable.meuse_emission_payload[:product_name]
      assert_equal "copilot_enterprise", emittable.meuse_emission_payload[:product_sku_name]
      assert_equal assignment.owner.id, emittable.meuse_emission_payload[:account_id]
      assert_nil emittable.meuse_emission_payload[:customer_id]
      assert_equal GlobalID.create(assignment.owner).to_s, emittable.meuse_emission_payload[:source_uri]
      refute_equal 0.0, emittable.meuse_emission_payload[:quantity]
    end

    test "it has a CE meuse payload for an organization on an pending CE trial with business on the CE plan" do
      assignment = create(:copilot_seat_assignment, :organization)
      org = assignment.owner
      business = create(:business)
      business.add_organization(org)

      # Create a pending Copilot Enterprise trial
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      create(:copilot_business_trial, :organization, state: "pending", trialable: org, copilot_plan: "enterprise")

      Copilot::Business.new(business).copilot_plan_enterprise!

      10.times do
        org.add_member(create(:user))
      end
      org.reload
      assignment.reload

      assert_equal 11, org.member_ids.count
      assert_equal 11, assignment.assignable_count
      assignment.convert_to_seats

      emittable = Copilot::Billing::Emittable.new(assignment.owner)

      assert_equal "copilot", emittable.meuse_emission_payload[:product_name]
      assert_equal "copilot_enterprise", emittable.meuse_emission_payload[:product_sku_name]
      assert_equal assignment.owner.id, emittable.meuse_emission_payload[:account_id]
      assert_nil emittable.meuse_emission_payload[:customer_id]
      assert_equal GlobalID.create(assignment.owner).to_s, emittable.meuse_emission_payload[:source_uri]
      refute_equal 0.0, emittable.meuse_emission_payload[:quantity]
    end

    test "it has a CB meuse payload for an organization on an active CE trial with business on the CE plan" do
      assignment = create(:copilot_seat_assignment, :organization)
      org = assignment.owner
      business = create(:business)
      business.add_organization(org)

      # Create an active Copilot Enterprise trial
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      create(:copilot_business_trial, :organization, :active, trialable: org, copilot_plan: "enterprise")

      Copilot::Business.new(business).copilot_plan_enterprise!

      10.times do
        org.add_member(create(:user))
      end
      org.reload
      assignment.reload

      assert_equal 11, org.member_ids.count
      assert_equal 11, assignment.assignable_count
      assignment.convert_to_seats

      emittable = Copilot::Billing::Emittable.new(assignment.owner)

      assert_equal "copilot", emittable.meuse_emission_payload[:product_name]
      assert_equal "copilot_for_business", emittable.meuse_emission_payload[:product_sku_name]
      assert_equal assignment.owner.id, emittable.meuse_emission_payload[:account_id]
      assert_nil emittable.meuse_emission_payload[:customer_id]
      assert_equal GlobalID.create(assignment.owner).to_s, emittable.meuse_emission_payload[:source_uri]
      refute_equal 0.0, emittable.meuse_emission_payload[:quantity]
    end

    test "it has a proper meuse payload for an organization on the basic plan" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      business = assignment.owner
      assert Copilot::Business.new(business).copilot_standalone?
      emittable = Copilot::Billing::Emittable.new(business)

      assert_equal "copilot", emittable.meuse_emission_payload[:product_name]
      assert_equal "copilot_standalone", emittable.meuse_emission_payload[:product_sku_name]
    end
  end
end if GitHub.copilot_enabled?
