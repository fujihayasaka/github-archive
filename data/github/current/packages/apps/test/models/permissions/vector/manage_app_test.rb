# typed: true
# frozen_string_literal: true

require "test_helper"

class Permissions::Enumerator::ManageAppTest < GitHub::TestCase

  fixtures do
    @org = create(:organization)
    @app = create(:integration, owner: @org)
    @member = create(:user, login: "org-member")
    @org.add_member(@member)
  end

  context "subject_ids" do
    test "returns nothing when an actor has no permissions on any apps" do
      subject_ids = Permissions::Enumerator.subject_ids_for_permission(action: :manage_app, actor_id: @member.id)

      assert_empty subject_ids
    end

    test "returns the subject IDs of Apps the actor has permission on" do
      result = Permissions::Granter.grant(actor_id: @member.id, action: :manage_app, subject_id: @app.id, entry_point: :test_case)
      assert_predicate result, :success?

      subject_ids = Permissions::Enumerator.subject_ids_for_permission(action: :manage_app, actor_id: @member.id)

      assert_equal [@app.id], subject_ids
    end
  end
end
