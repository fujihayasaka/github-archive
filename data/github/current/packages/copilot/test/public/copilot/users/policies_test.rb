
# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUsersPoliciesTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "#all_policies" do
    test "returns an empty array when the user has no seats" do
      copilot_user = Copilot::User.new(create(:user))
      actual = copilot_user.all_policies
      assert_empty actual
    end

    test "returns an array of configurations when the user has seats" do
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
      actual = Copilot::User.new(user).all_policies

      assert_equal 3, actual.length
      assert_equal :business, T.must(T.must(T.must(actual.first)))[:type]
      assert_equal org.business.slug, T.must(T.must(actual.first))[:name]
      assert_equal "blocked", T.must(T.must(actual.first)[:config].public_code_suggestions)
      assert_equal :organization, actual.second[:type]
      assert_equal org.display_login, actual.second[:name]
      refute actual.second[:config].cli_enabled?
      assert_equal :organization, actual.third[:type]
      assert_equal org2.display_login, actual.third[:name]
      assert actual.third[:config].cli_enabled?
    end
  end unless GitHub.enterprise?

  fixtures do
    @user = create(:user)
    @copilot_enterprise = create(:copilot_business, :enterprise_plan).freeze
    @copilot_enterprise.enable_copilot_for_all_organizations!
    @copilot_enterprise2 = create(:copilot_business, :enterprise_plan).freeze
    @copilot_enterprise2.enable_copilot_for_all_organizations!
    @copilot_enterprise3 = create(:copilot_business, :enterprise_plan).freeze
    @copilot_enterprise3.enable_copilot_for_all_organizations!
    @org = create(:copilot_for_business_enabled_organization)
    @org2 = create(:copilot_for_business_enabled_organization)
    @org3 = create(:copilot_for_business_enabled_organization)
  end

  context "#enabled_most_restrictive?" do
    test "returns true when only one org enables" do
      @copilot_enterprise.add_organization(@org)
      @copilot_enterprise.add_organization(@org2)
      @org.add_member(@user)
      @org2.add_member(@user)

      assignment = create(:copilot_seat_assignment, :organization, organization: @org)
      assignment.convert_to_seats

      assignment2 = create(:copilot_seat_assignment, :organization, organization: @org2)
      assignment2.convert_to_seats

      Copilot::Organization.new(@org2).cli_enabled!
      all_policies = Copilot::User.new(@user).all_policies
      actual = Copilot::User.new(@user).enabled_most_restrictive?(all_policies, :cli)
      assert actual
    end

    test "returns false when only one org disables" do
      @copilot_enterprise.add_organization(@org)
      @copilot_enterprise.add_organization(@org2)
      @org.add_member(@user)
      @org2.add_member(@user)

      assignment = create(:copilot_seat_assignment, :organization, organization: @org)
      assignment.convert_to_seats

      assignment2 = create(:copilot_seat_assignment, :organization, organization: @org2)
      assignment2.convert_to_seats

      @copilot_enterprise.cli_enabled!
      Copilot::Organization.new(@org2).cli_disabled!
      all_policies = Copilot::User.new(@user).all_policies
      actual = Copilot::User.new(@user).enabled_most_restrictive?(all_policies, :cli)
      refute actual
    end
  end unless GitHub.enterprise?

  context "#enabled_least_restrictive?" do
    test "returns true when only one org enables" do
      @copilot_enterprise.add_organization(@org)
      @copilot_enterprise.add_organization(@org2)
      @org.add_member(@user)
      @org2.add_member(@user)

      assignment = create(:copilot_seat_assignment, :organization, organization: @org)
      assignment.convert_to_seats

      assignment2 = create(:copilot_seat_assignment, :organization, organization: @org2)
      assignment2.convert_to_seats

      Copilot::Organization.new(@org2).cli_enabled!
      all_policies = Copilot::User.new(@user).all_policies
      actual = Copilot::User.new(@user).enabled_least_restrictive?(all_policies, :cli)
      assert actual
    end

    test "returns false when only one org enables but one enterprise disables" do
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

      org.add_member(user)
      org2.add_member(user)

      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats

      assignment2 = create(:copilot_seat_assignment, :organization, organization: org2)
      assignment2.convert_to_seats

      copilot_enterprise.cli_disabled!
      copilot_enterprise2.cli_enabled!
      Copilot::Organization.new(org).cli_disabled!
      Copilot::Organization.new(org2).cli_enabled!
      all_policies = Copilot::User.new(user).all_policies
      actual = Copilot::User.new(user).enabled_least_restrictive?(all_policies, :cli)
      refute actual
    end

    test "returns true when one org enables and another org disables" do
      @copilot_enterprise.add_organization(@org)
      @copilot_enterprise.add_organization(@org2)
      @org.add_member(@user)
      @org2.add_member(@user)

      assignment = create(:copilot_seat_assignment, :organization, organization: @org)
      assignment.convert_to_seats

      assignment2 = create(:copilot_seat_assignment, :organization, organization: @org2)
      assignment2.convert_to_seats

      Copilot::Organization.new(@org2).cli_enabled!
      Copilot::Organization.new(@org).cli_disabled!
      all_policies = Copilot::User.new(@user).all_policies
      actual = Copilot::User.new(@user).enabled_least_restrictive?(all_policies, :cli)
      assert actual
    end
  end unless GitHub.enterprise?

  context "#policy_breakdown" do
    test "returns breakdown of policies" do
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

      org.add_member(user)
      org2.add_member(user)

      assignment = create(:copilot_seat_assignment, :organization, organization: org)
      assignment.convert_to_seats

      assignment2 = create(:copilot_seat_assignment, :organization, organization: org2)
      assignment2.convert_to_seats

      copilot_enterprise.cli_disabled!
      copilot_enterprise2.cli_enabled!
      all_policies = Copilot::User.new(user).all_policies
      breakdown = Copilot::User.new(user).policy_breakdown(all_policies, :cli)
      assert_equal 2, T.must(breakdown[:enabled]).length
      assert_equal 2, T.must(breakdown[:disabled]).length
      assert_empty breakdown[:unconfigured]
      assert_empty breakdown[:no_policy]
    end
  end unless GitHub.enterprise?
end
