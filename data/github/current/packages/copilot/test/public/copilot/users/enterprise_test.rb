# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUsersEnterpriseTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include ResiliencyHelpers

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @org.add_member(@user)
  end

  setup do
    @copilot_user = Copilot::User.new(@user)
  end

  context "#copilot_businesses" do
    test "returns an empty array when the user has no seats" do
      assert_empty @copilot_user.copilot_businesses
    end

    test "returns a standalone business" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      assignment.convert_to_seats

      seat = assignment.seats.first
      user = seat.assigned_user

      copilot_user = Copilot::User.new(user)
      assert_equal assignment.owner_id, T.must(copilot_user.copilot_businesses.first).id
    end

    test "returns a single seat business" do
      seat = create(:copilot_seat)
      user = seat.assigned_user

      copilot_user = Copilot::User.new(user)
      assert_equal seat.organization.business.id, T.must(copilot_user.copilot_businesses.first).id
    end

    # We have a test above to ensure that a single business is returned when only one exists
    test "returns multiple businesses", skip_with_all_emus: true do
      seat = create(:copilot_seat)
      user = seat.assigned_user

      org = create(:copilot_for_business_enabled_organization)
      org.add_member(user)
      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats


      copilot_user = Copilot::User.new(user)
      assert_equal 2, copilot_user.copilot_businesses.length
    end
  end

  context "#copilot_organization" do
    test "no Copilot orgs" do
      assert_nil @copilot_user.copilot_organization
    end

    test "returns the only org if they have a seat" do
      create(:copilot_seat, organization: @org, assigned_user: @user)
      assert_equal @org,
        @copilot_user.copilot_organization.organization_object
    end

    test "returns the most restrictive public code suggestions org if multiple" do
      org1 = create(:organization)
      create(:copilot_configuration, :organization,
             configurable: org1,
             public_code_suggestions: :allowed)
      org1.add_member(@user)
      @user.reload
      create(:copilot_seat, organization: org1, assigned_user: @user)

      org2 = create(:organization)
      create(:copilot_configuration, :organization,
             configurable: org2,
             public_code_suggestions: :blocked)
      org2.add_member(@user)
      @user.reload
      create(:copilot_seat, organization: org2, assigned_user: @user)

      org3 = create(:organization)
      create(:copilot_configuration, :organization,
             configurable: org3,
             public_code_suggestions: :unconfigured)
      org3.add_member(@user)
      @user.reload
      create(:copilot_seat, organization: org3, assigned_user: @user)

      assert_equal org2,
        @copilot_user.copilot_organization.organization_object
    end
  end

  context "#orgs_using_copilot_for_business" do
    test "returns an empty array when the user has no seats" do
      assert_empty @copilot_user.orgs_using_copilot_for_business
    end

    test "returns an array of organizations when the user has seats" do
      create(:copilot_seat, assigned_user: @user, organization: @org)

      actual = @copilot_user.orgs_using_copilot_for_business

      assert_equal 1, actual.length
      assert_equal @org.id, T.must(actual.first).organization_object.id
    end

    test "returns an array of organizations when the user has seat assignments" do
      create(:copilot_seat_assignment, :user, assignable: @user, organization: @org)

      actual = @copilot_user.orgs_using_copilot_for_business

      assert_equal 1, actual.length
      assert_equal @org.id, T.must(actual.first).organization_object.id
    end

    test "returns an array of organizations when the user has seats and assignments" do
      org = create(:organization)
      org.add_member(@user)
      @user.reload
      create(:copilot_seat_assignment, :user, assignable: @user, organization: org)
      create(:copilot_seat, assigned_user: @user, organization: @org)

      actual = @copilot_user.orgs_using_copilot_for_business

      assert_equal 2, actual.length
      assert_includes actual.map(&:id), org.id
      assert_includes actual.map(&:id), @org.id
    end

    test "what if the organization went away?" do
      org = create(:organization)
      org.add_member(@user)
      @user.reload
      seat_assignment = create(:copilot_seat_assignment, :user, assignable: @user, organization: org)
      create(:copilot_seat, assigned_user: @user, organization: @org)

      seat_assignment.update_column(:organization_id, T.must(T.must(::Organization.last).id) + 1000)

      actual = @copilot_user.orgs_using_copilot_for_business

      assert_equal 1, actual.length
      refute_includes actual.map(&:id), org.id
      assert_includes actual.map(&:id), @org.id
    end
  end

  context "#async_seats" do
    test "gracefully degrades when copilot cluster is unavailable" do
      prevent_connections_to(ApplicationRecord::Copilot) do
        assert_equal [], @copilot_user.async_seats.sync
      end
    end
  end

  context "#async_businesses_using_copilot_for_business" do
    test "returns an empty array when the user has no seats" do
      copilot_user = Copilot::User.new(create(:user))
      assert_empty copilot_user.async_businesses_using_copilot_for_business.sync
    end

    test "returns an array of businesses when the user has seats", skip_with_all_emus: true do
      seat = create(:copilot_seat)
      user = seat.assigned_user

      org = create(:copilot_for_business_enabled_organization)
      org.add_member(user)
      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats

      actual = Copilot::User.new(user).async_businesses_using_copilot_for_business.sync

      assert_equal 2, actual.length
      assert_equal org.business.id, T.must(actual.second).id
    end

    test "returns an array of one element in EMU mode" do
      seat = create(:copilot_seat)
      user = seat.assigned_user

      org = create(:copilot_for_business_enabled_organization)
      org.add_member(user)
      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats

      actual = Copilot::User.new(user).async_businesses_using_copilot_for_business.sync

      assert(actual.is_a?(Array))
      assert_equal 1, actual.size
      assert_equal actual.first, org.business
    end if TestEnv.test_with_all_emus?

    test "returns an array of businesses even when seat assignments are pending cancellation", skip_with_all_emus: true do
      enable_feature_flag(:copilot_async_businesses_include_revokable)
      user = create(:user)

      org = create(:copilot_for_business_enabled_organization)
      org.add_member(user)
      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats
      assignment.update(pending_cancellation_date: Date.current)
      actual = Copilot::User.new(user).async_businesses_using_copilot_for_business.sync

      assert_equal 1, actual.length
      assert_equal org.business.id, T.must(actual.first).id
    end
  end

  context "#async_businesses_and_orgs_using_copilot_for_business" do
    test "returns an empty array when the user has no seats" do
      copilot_user = Copilot::User.new(create(:user))
      actual = copilot_user.async_businesses_and_orgs_using_copilot_for_business.sync
      assert_empty actual[:businesses]
      assert_empty actual[:organizations]
    end

    test "returns an array of businesses and organizations when the user has seats", skip_with_all_emus: true do
      seat = create(:copilot_seat)
      user = seat.assigned_user

      org = create(:copilot_for_business_enabled_organization)
      org.add_member(user)
      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats

      actual = Copilot::User.new(user).async_businesses_and_orgs_using_copilot_for_business.sync

      assert_equal 2, T.must(actual[:businesses]).length
      assert_equal 2, T.must(actual[:organizations]).length
      assert_equal org.business.id, T.must(T.must(actual[:businesses])[1]).id
      assert_equal org.id, T.must(T.must(actual[:organizations])[1]).id
    end

    test "returns an array of one business and organizations when the user has seats" do
      seat = create(:copilot_seat)
      user = seat.assigned_user

      org = create(:copilot_for_business_enabled_organization)
      org.add_member(user)
      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats

      actual = Copilot::User.new(user).async_businesses_and_orgs_using_copilot_for_business.sync

      assert_equal 1, T.must(actual[:businesses]).length
      assert_equal 2, T.must(actual[:organizations]).length
      assert_equal org.id, T.must(T.must(actual[:organizations])[1]).id
    end if TestEnv.test_with_all_emus?
  end

  context "#async_collated_copilot_for_business_configurations" do
    test "returns an empty array when the user has no seats" do
      copilot_user = Copilot::User.new(create(:user))
      actual = copilot_user.async_collated_copilot_for_business_configurations.sync
      assert_empty actual
    end

    test "returns an array of configurations when the user has seats", skip_with_all_emus: true do
      user = create(:user)
      copilot_enterprise = create(:copilot_business, :enterprise_plan)
      copilot_enterprise.enable_copilot_for_all_organizations!
      org = create(:copilot_for_business_enabled_organization, business: Business.find_by(id: copilot_enterprise.id))
      org2 = create(:copilot_for_business_enabled_organization, business: Business.find_by(id: copilot_enterprise.id))
      org.add_member(user)
      org2.add_member(user)

      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats

      assignment2 = create(:copilot_seat_assignment, :organization, organization: org2)
      assignment2.convert_to_seats

      Copilot::Organization.new(org2).cli_enabled!
      actual = Copilot::User.new(user).async_collated_copilot_for_business_configurations.sync

      assert_equal 3, actual.length
      assert_equal org.business.id, T.must(T.must(actual.first)[:business]).id
      assert_equal "Business", T.must(T.must(actual.first)[:config].configurable_type)
      assert_equal "blocked", T.must(T.must(actual.first)[:config].public_code_suggestions)
      assert_equal "Organization", T.must(T.must(actual.second)[:config].configurable_type)
      assert T.must(T.must(actual.second)[:config].cli_enabled?)
      assert_equal "Organization", T.must(T.must(actual.third)[:config].configurable_type)
      assert T.must(T.must(actual.third)[:config].cli_enabled?)
    end

    test "returns an array of configurations when the user has seats with multiple enterprises", skip_with_all_emus: true do
      user = create(:user)
      copilot_enterprise = create(:copilot_business, :enterprise_plan)
      copilot_enterprise.enable_copilot_for_all_organizations!
      copilot_enterprise2 = create(:copilot_business, :enterprise_plan)
      copilot_enterprise2.enable_copilot_for_all_organizations!
      org = create(:copilot_for_business_enabled_organization, business: Business.find_by(id: copilot_enterprise.id))
      org2 = create(:copilot_for_business_enabled_organization, business: Business.find_by(id: copilot_enterprise2.id))
      org.add_member(user)
      org2.add_member(user)

      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats

      assignment2 = create(:copilot_seat_assignment, :organization, organization: org2)
      assignment2.convert_to_seats

      Copilot::Organization.new(org2).cli_enabled!
      Copilot::Organization.new(org).cli_enabled!
      actual = Copilot::User.new(user).async_collated_copilot_for_business_configurations.sync

      assert_equal 4, actual.length
      assert_equal org.business.id, T.must(T.must(actual.first)[:business]).id
      assert_equal "Business", T.must(T.must(actual.first)[:config].configurable_type)
      assert_equal "blocked", T.must(T.must(actual.first)[:config].public_code_suggestions)
      assert_equal "Business", T.must(T.must(actual.second)[:config].configurable_type)
      assert T.must(T.must(actual.second)[:config].cli_enabled?)
      assert_equal "Organization", T.must(T.must(actual.third)[:config].configurable_type)
      assert T.must(T.must(actual.third)[:config].cli_enabled?)
    end

    # Here we test a case that will pass both in EMU mode and regular
    test "returns a standalone business" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      assignment.convert_to_seats

      seat = assignment.seats.first
      user = seat.assigned_user
      Copilot::Business.new(assignment.owner).cli_enabled!

      copilot_user = Copilot::User.new(user)
      assert_equal assignment.owner_id, T.must(copilot_user.copilot_businesses.first).id
      actual = Copilot::User.new(user).async_collated_copilot_for_business_configurations.sync
      assert_equal 1, actual.length
      assert_equal "Business", T.must(T.must(actual.first)[:config].configurable_type)
      assert_equal "enabled", T.must(T.must(actual.first)[:config].cli)
    end

  end

  context "#copilot_standalone_businesses" do
    test "returns the business when the user is a member of a single basic business" do
      business = create :business
      business.update(seats_plan_type: :basic)
      create :business_user_account, business: business, user: @user, business_roles_bitfield: 0
      assert_equal @copilot_user.copilot_standalone_businesses.pluck(:id), [business.id]
    end

    test "returns all businesses when the user is a member of a multiple basic businesses" do
      business = create :business
      business.update(seats_plan_type: :basic)
      create :business_user_account, business: business, user: @user, business_roles_bitfield: 0

      business2 = create :business
      business2.update(seats_plan_type: :basic)
      create :business_user_account, business: business2, user: @user, business_roles_bitfield: 0

      assert_same_elements [business.id, business2.id].uniq, @copilot_user.copilot_standalone_businesses.pluck(:id)
    end

    test "returns the business when the user is a member of a single basic EMU business" do
      emu = create :emu
      business = emu.enterprise_managed_business
      business.update(seats_plan_type: :basic)
      create :business_user_account, business: business, user: @user, business_roles_bitfield: 0
      assert_equal @copilot_user.copilot_standalone_businesses.pluck(:id), [business.id]
    end
  end

  context "#enterprise_team_ids" do
    test "returns an empty array when the user is not enterprise managed" do
      assignment = create(:copilot_seat_assignment, :organization)
      assignment.convert_to_seats

      assert_empty Copilot::User.new(assignment.seats.first.assigned_user).enterprise_team_ids
    end

    test "returns an array of enterprise team ids when user belongs to a non-emu basic enterprise" do
      biz = create(:business)
      biz.update(seats_plan_type: :basic)

      user = create(:user)

      biz.add_user_accounts([user.id], business_roles_bitfield: 0)

      team = create(:enterprise_team, business: biz)
      team.enterprise_team_memberships.create!(user_id: user.id)

      Copilot::Business.new(biz).enable_copilot!
      assignment = Copilot::SeatAssignment.new(
        owner_id: team.business_id,
        owner_type: "Business",
        assignable_type: "EnterpriseTeam",
        assignable_id: team.id,
        assigning_user: team.business.owners.first,
      )
      assignment.save!
      assignment.convert_to_seats

      assert_equal 1, Copilot::User.new(user).enterprise_team_ids.count
      assert_equal team.id, Copilot::User.new(user).enterprise_team_ids.first
    end

    test "returns an array of group ids when the user is enterprise managed" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      user = User.find(assignment.assignable.member_user_ids.first)

      assert_equal Copilot::User.new(user).enterprise_team_ids.first, assignment.assignable.id
    end
  end
end if GitHub.copilot_enabled?
