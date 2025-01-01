# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationProgrammaticAccessGrantTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @user = create(:user)
    @pat  = create(:user_programmatic_access, owner: @user)

    @org = create(:organization, admin: @user)

    @subject = make_programmatic_access_grant(
      access: @pat, target: @org, requester: @user,
      permissions: { "members" => :read }
    )

    assert_predicate @subject, :persisted?
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
      grants = OrganizationProgrammaticAccessGrant.with_bot(ids: [@subject.id])
      assert_equal [@subject], grants
      refute_nil grants.first&.bot
    end
  end

  context "requests" do
    test "destroy any associated request in cascade" do
      org = create(:organization)
      org.add_member(@user)

      grant = make_programmatic_access_grant(
        access: @pat, target: org, requester: @user,
        permissions: { "members" => :read }
      )

      make_programmatic_access_grant_request(
        access: @pat, target: org, permissions: { "members" => :write }
      )

      scope = OrganizationProgrammaticAccessGrantRequest.where(grant: grant)

      assert_difference -> { scope.count }, -1 do
        grant.destroy
      end
    end
  end

  context "instrumentation" do
    test "instruments deletion" do
      events = subscribe "personal_access_token.access_revoked"
      @subject.destroy

      expected_payload = {
        user_programmatic_access_id: @pat.id,
        user_programmatic_access_name: @pat.name,
        organization_programmatic_access_grant_id: @subject.id,
        requester: @user.login,
        requester_id: @user.id,
        target: @org.login,
        target_id: @org.id,
        org: @org.login,
        org_id: @org.id,
        reason: nil,
        repository_selection: @subject.repository_selection,
        permissions: { "members" => :read },
        token_id: @pat.id,
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
    assert_equal @org, @subject.target_for_conditional_access
  end

  test "does not delete organization PAT grants when user membership is downgraded", feature_enabled: :skip_org_pat_grant_removal_when_demoting_admin do
    another_admin = create(:user)
    @org.add_admin(another_admin)

    grant = make_programmatic_access_grant(
      access: @pat, target: @org, requester: @user,
      permissions: { "members" => :read }
    )

    perform_enqueued_jobs(only: RevokeOrgMemberProgrammaticAccessGrantsJob) do
      assert_no_difference(-> { OrganizationProgrammaticAccessGrant.count }) do
        @org.update_member(@user, action: :read)
      end
    end
  end
end
