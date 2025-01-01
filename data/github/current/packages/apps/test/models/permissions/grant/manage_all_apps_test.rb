# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/permissions_helper"

class Permissions::Granter::ManageAllAppsTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @org = create(:organization)
    @member = create(:user, login: "orgMember")
    @org.add_member(@member)
  end

  context "#grant!" do
    test "grants permission when an actor_id and subject_id are supplied" do
      refute_granted_in_permissions_table(actor_id: @member.id, subject_id: @org.id, subject_type: Permissions::Granters::ManageAllApps::SUBJECT_TYPE)

      granter = Permissions::Granters::ManageAllApps.new
      result = granter.grant!(actor_id: @member.id, subject_id: @org.id, entry_point: :test_case)

      assert_predicate result, :success?
      assert_granted_in_permissions_table(actor_id: @member.id, subject_id: @org.id, subject_type: Permissions::Granters::ManageAllApps::SUBJECT_TYPE)
    end
  end

  context "#revoke!" do
    test "revokes permission when an actor_id and subject_id are supplied" do
      granter = Permissions::Granters::ManageAllApps.new
      granter.grant!(actor_id: @member.id, subject_id: @org.id, entry_point: :test_case)

      assert_granted_in_permissions_table(actor_id: @member.id, subject_id: @org.id, subject_type: Permissions::Granters::ManageAllApps::SUBJECT_TYPE)

      result = granter.revoke!(actor_id: @member.id, subject_id: @org.id)
      assert_predicate result, :success?
      refute_granted_in_permissions_table(actor_id: @member.id, subject_id: @org.id, subject_type: Permissions::Granters::ManageAllApps::SUBJECT_TYPE)
    end
  end
end
