# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class Permissions::Granter::ManageAppTest < GitHub::TestCase
  include PermissionsHelper

  fixtures do
    @integration = create(:integration)
    @user = create(:user)
  end

  context "#grant!" do
    test "grants permission when an actor_id and subject_id are supplied" do
      refute_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: Permissions::Granters::ManageApp::SUBJECT_TYPE)

      granter = Permissions::Granters::ManageApp.new
      result = granter.grant!(actor_id: @user.id, subject_id: @integration.id, entry_point: :test_case)

      assert_predicate result, :success?

      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: Permissions::Granters::ManageApp::SUBJECT_TYPE)
    end
  end

  context "#revoke!" do
    test "revokes permission when an actor_id and subject_id are supplied" do
      granter = Permissions::Granters::ManageApp.new
      result = granter.grant!(actor_id: @user.id, subject_id: @integration.id, entry_point: :test_case)

      assert_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: Permissions::Granters::ManageApp::SUBJECT_TYPE)

      result = granter.revoke!(actor_id: @user.id, subject_id: @integration.id)
      assert_predicate result, :success?
      refute_granted_in_permissions_table(actor_id: @user.id, subject_id: @integration.id, subject_type: Permissions::Granters::ManageApp::SUBJECT_TYPE)
    end
  end
end
