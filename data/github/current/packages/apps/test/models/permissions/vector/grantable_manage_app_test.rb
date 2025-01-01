# typed: true
# frozen_string_literal: true

require "test_helper"

class Permissions::Enumerator::GrantableManageAppTest < GitHub::TestCase

  fixtures do
    @org = create(:organization)
    @app = create(:integration, owner: @org)
  end

  test "returns no actor IDs when there are only Organization owners" do
    actor_ids = Permissions::Enumerator.actor_ids_with_permission(action: :grantable_manage_app, subject_id: @app.id, context: { owner_id: @org.id })

    assert_predicate actor_ids, :empty?
  end

  test "returns ids of organization members that have not already been granted permission" do
    member = create(:user)
    @org.add_member(member)

    actor_ids = Permissions::Enumerator.actor_ids_with_permission(action: :grantable_manage_app, subject_id: @app.id, context: { owner_id: @org.id })

    assert_includes actor_ids, member.id
  end

  test "does not return actor IDs of members that have already been granted permission" do
    member = create(:user)
    @org.add_member(member)
    result = Permissions::Granter.grant(actor_id: member.id, action: :manage_app, subject_id: @app.id, entry_point: :test_case)
    assert_predicate result, :success?

    actor_ids = Permissions::Enumerator.actor_ids_with_permission(action: :grantable_manage_app, subject_id: @app.id, context: { owner_id: @org.id })

    refute_includes actor_ids, member.id
  end

  test "does not return actor IDs of members that have been granted permission to manage all apps" do
    member = create(:user)
    @org.add_member(member)
    result = Permissions::Granter.grant(actor_id: member.id, action: :manage_all_apps, subject_id: @org.id, entry_point: :test_case)
    assert_predicate result, :success?

    actor_ids = Permissions::Enumerator.actor_ids_with_permission(action: :grantable_manage_app, subject_id: @app.id, context: { owner_id: @org.id })

    refute_includes actor_ids, member.id
  end
end
