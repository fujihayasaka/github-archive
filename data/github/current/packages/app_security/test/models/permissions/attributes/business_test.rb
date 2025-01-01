# typed: true
# frozen_string_literal: true
require "test_helper"

class Permissions::Attributes::BusinessTest < GitHub::TestCase

  setup do
    @actor = create(:user)
    @business = create :business
    @subject = @business.permissions_wrapper.freeze
    GitHub.flipper[:enterprise_enforce_upfront_attribute].enable
  end

  context "subject attributes" do
    test "subject attributes" do
      attrs = @subject.subject_attributes
      assert_equal({ "subject.type" => "Business", "subject.id" => @business.id, "subject.business.id" => @business.id }, attrs)
    end
  end

  context "actor attributes" do
    test "don't serialize actor attributes when actor is not a user" do
      org = create :organization, business: @business
      team = create :team, organization: org
      EnterpriseTeam.stubs(:all_team_ids_for).returns([42, 777])
      EnterpriseTeam.stubs(:all_visible_team_ids_for).returns([42, 777])

      attrs = @subject.serialized_actor_attributes(team)

      assert_nil attrs.find { |attr| attr.id == "business.enterprise_teams.for_user" }
    end

    test "don't serialize actor attributes when FF disabled" do
      GitHub.flipper[:enterprise_enforce_upfront_attribute].disable

      EnterpriseTeam.stubs(:all_team_ids_for).returns([42, 777])
      EnterpriseTeam.stubs(:all_visible_team_ids_for).returns([42, 777])

      attrs = @subject.serialized_actor_attributes(@actor)

      assert_nil attrs.find { |attr| attr.id == "business.enterprise_teams.for_user" }
    end

    test "serialize actor attributes" do
      EnterpriseTeam.stubs(:all_team_ids_for).with(@business, @actor).returns([42, 777])
      EnterpriseTeam.stubs(:all_visible_team_ids_for).with(@actor, business_ids: [@business.id]).returns([42, 777])

      attrs = @subject.serialized_actor_attributes(@actor)

      assert_equal [42, 777], attrs.find { |attr| attr.id == "business.enterprise_teams.for_user" }.value.integer_list_value.values
    end
  end
end
