# typed: true
# frozen_string_literal: true

require "test_helper"

class UserProgrammaticAccessGrantTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @user = create(:user)
    @pat = create(:user_programmatic_access, owner: @user)

    @repo_a = create(:private_repository, :minimal, owner: @user)
    @repo_b = create(:private_repository, :minimal, owner: @user)

    @subject = make_programmatic_access_grant(
      access: @pat,
      target: @user,
      repositories: [@repo_a],
      permissions: { "emails" => :read, "metadata" => :read, "contents" => :read },
      repository_selection: :subset,
    )
  end

  context "#validations" do
    test "requires a target" do
      @subject.update(target: nil)

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:target], "must exist"
    end

    test "requires a parent user_programmatic_access" do
      @subject.update(user_programmatic_access: nil)

      refute_predicate @subject, :valid?
      assert_includes @subject.errors[:user_programmatic_access], "must exist"
    end
  end

  context ".with_bot" do
    test "it loads grants with bots" do
      grants = UserProgrammaticAccessGrant.with_bot(ids: [@subject.id])
      assert_equal [@subject], grants
      refute_nil grants.first.bot
    end
  end

  context "#repository_selection" do
    test "it's :all when granting on all repos" do
      pat = create(:user_programmatic_access, owner: @user)
      grant = make_programmatic_access_grant(
        access: pat,
        target: @user,
        permissions: { "emails" => :read, "metadata" => :read, "contents" => :read },
        repository_selection: :all,
      )

      assert_equal "all", grant.repository_selection
    end

    test "it's :subset when granting on specific repos" do
      assert_equal "subset", @subject.repository_selection
    end

    test "it's :none when no repo permissions are granted" do
      pat = create(:user_programmatic_access, owner: @user)
      grant = make_programmatic_access_grant(
        access: pat,
        target: @user,
        permissions: { "emails" => :read },
      )

      assert_equal "none", grant.repository_selection
    end
  end

  test "request is nil" do
    assert_nil @subject.request
  end

  context "instrumentation" do
    test "instruments creation" do
      events = subscribe "personal_access_token.access_granted"

      result = ProgrammaticAccess.create_with_grant_and_token(
        actor: @user,
        target: @user,
        access_token_attributes: {
          name: "First Name",
          default_expires_at: "7",
          description: "my token",
        },
        permissions: { "metadata" => :read },
        repositories: [],
        repository_selection: :all,
        entry_point: :test_case
      )

      access = result.access
      grant = access.grant

      expected_payload = {
        user_programmatic_access_id: access.id,
        user_programmatic_access_name: access.name,
        user_programmatic_access_grant_id: grant.id,
        requester: @user.login,
        requester_id: @user.id,
        target: @user.login,
        target_id: @user.id,
        user: @user.login,
        user_id: @user.id,
        repository_selection: grant.repository_selection,
        permissions: { "metadata" => :read }
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "instruments deletion" do
      events = subscribe "personal_access_token.access_revoked"
      @subject.destroy

      expected_payload = {
        user_programmatic_access_id: @pat.id,
        user_programmatic_access_name: @pat.name,
        user_programmatic_access_grant_id: @subject.id,
        requester: @user.login,
        requester_id: @user.id,
        target: @user.login,
        target_id: @user.id,
        user: @user.login,
        user_id: @user.id,
        repository_selection: "subset",
        repositories: [@repo_a.id],
        permissions: { "contents" => :read, "metadata" => :read, "emails" => :read }
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end
  end

  context "#approvable_by?" do
    test "returns false" do
      refute @subject.approvable_by?(@user)
    end
  end

  test "#target_for_conditonal_access aliases to the target" do
    assert_equal @user, @subject.target_for_conditional_access
  end
end
