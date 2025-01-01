# typed: true
# frozen_string_literal: true

require "set"
require "test_helper"

class RepositoryBulkInviteJobTest < GitHub::TestCase
  include HydroTestHelpers
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @owner = create(:user, login: "owner")
    @invitee = create(:user, login: "invite", email: "invite@me.github")
    @expired_invitee = create(:user, login: "expired-invite", email: "expired-invite@me.github")
    @repo = create(:repository, owner: @owner)

    @pending_repo_invitation = create(
      :repository_invitation,
      repository: @repo,
      inviter: @owner,
      invitee: @invitee,
      permissions: :write
    )
    Timecop.freeze(Time.zone.now - GitHub.invitation_expiry_period.days - 1.day) do
      @expired_repo_invitation = create(
        :repository_invitation,
        repository: @repo,
        inviter: @owner,
        invitee: @expired_invitee,
        permissions: :write
      )
    end
  end

  # Test helper to assert the Hydro message sent by RepositoryBulkInviteJob, assumes no errors and checks for 1 hydro event
  private def assert_repo_bulk_invite_hydro(repo, successful_users, successful_emails)
    serialized_actor = Hydro::EntitySerializer.user(@owner.reload)
    serialized_repo = Hydro::EntitySerializer.repository(repo.reload)
    expected_hydro_message = {
      actor: serialized_actor,
      repository: serialized_repo,
      successful_user_invites: successful_users,
      successful_email_invites: successful_emails,
      failed_user_invites: [],
      failed_email_invites: [],
      organization: nil
    }

    assert_hydro_published(expected_hydro_message, schema: "github.v1.RepositoryBulkInvite")
    assert_hydro_messages(count: 1, schema: "github.v1.RepositoryBulkInvite")
  end

  # Test helper to assert the Hydro message hash (i.e. hydro_messages(x).first) sent by RepositoryBulkInviteJob.
  # This should be used in cases where there are multiple entities in the repeated fields of the hydro message
  # schema, to avoid gauntlet test failures checking for exact ordering of the repeated fields (we only care if
  # the entities are included, not their ordering)
  private def assert_repo_bulk_invite_hydro_hash(hydro_hash, repo, successful_users, successful_emails)
    assert_equal @owner.id, hydro_hash[:actor][:id]
    assert_equal repo.id, hydro_hash[:repository][:id]

    assert_equal successful_users.length, hydro_hash[:successful_user_invites].length
    successful_users.map { |user_id| assert_includes hydro_hash[:successful_user_invites], user_id }

    assert_equal successful_emails.length, hydro_hash[:successful_email_invites].length
    successful_emails.map { |email| assert_includes hydro_hash[:successful_email_invites], email }

    assert_equal [], hydro_hash[:failed_user_invites]
    assert_equal [], hydro_hash[:failed_email_invites]
    assert_nil hydro_hash[:organization]
  end

  test "creates reinvitation for a pending repository invite" do
    result = RepositoryBulkInviteJob.perform_now(@owner, [@pending_repo_invitation.id])

    assert_empty RepositoryInvitation.where(id: @pending_repo_invitation.id)
    assert_empty result[:errors]
    assert_equal 1, result[:successes].length
    assert_equal @invitee.id, result[:successes].first
    assert_repo_bulk_invite_hydro(@repo, [@invitee.id], [])
  end

  test "creates reinvitation for an expired repository invite" do
    result = RepositoryBulkInviteJob.perform_now(@owner, [@expired_repo_invitation.id])

    assert_empty RepositoryInvitation.where(id: @expired_repo_invitation.id)
    assert_empty result[:errors]
    assert_equal 1, result[:successes].length
    assert_equal @expired_invitee.id, result[:successes].first
    assert_repo_bulk_invite_hydro(@repo, [@expired_invitee.id], [])
  end

  test "creates reinvitations for both pending and expired repository invites" do
    result = RepositoryBulkInviteJob.perform_now(@owner, [@pending_repo_invitation.id, @expired_repo_invitation.id])

    assert_empty RepositoryInvitation.where(id: @pending_repo_invitation.id)
    assert_empty RepositoryInvitation.where(id: @expired_repo_invitation.id)
    assert_empty result[:errors]
    assert_equal 2, result[:successes].length
    assert_includes result[:successes], @invitee.id
    assert_includes result[:successes], @expired_invitee.id

    hydro_msg = hydro_messages(schema: "github.v1.RepositoryBulkInvite").first
    assert_repo_bulk_invite_hydro_hash(hydro_msg, @repo, [@invitee.id, @expired_invitee.id], [])
  end

  test "works for email invitations" do
    new_invitee = create(:user, login: "email-invite", email: "email-invite@me.github")
    email_repo_invitation = create(
      :repository_invitation,
      repository: @repo,
      inviter: @owner,
      invitee: nil,
      email: new_invitee.email,
      permissions: :write
    )
    result = RepositoryBulkInviteJob.perform_now(@owner, [email_repo_invitation.id])

    assert_empty RepositoryInvitation.where(id: email_repo_invitation.id)
    assert_empty result[:errors]
    assert_equal 1, result[:successes].length
    assert_equal new_invitee.email, result[:successes].first
    assert_repo_bulk_invite_hydro(@repo, [], [new_invitee.email])
  end

  test "does not create reinvitation for a repository invite that has already been reinvited" do
    RepositoryBulkInviteJob.perform_now(@owner, [@pending_repo_invitation.id])
    assert_repo_bulk_invite_hydro(@repo, [@invitee.id], [])
    reset_hydro

    result = RepositoryBulkInviteJob.perform_now(@owner, [@pending_repo_invitation.id])

    assert_empty result[:errors]
    assert_empty result[:successes]
    assert_hydro_messages(count: 0, schema: "github.v1.RepositoryBulkInvite")
  end

  test "does not create reinvitation for a repository invite that has already been canceled" do
    @pending_repo_invitation.cancel!(actor: @owner)
    result = RepositoryBulkInviteJob.perform_now(@owner, [@pending_repo_invitation.id])

    assert_empty result[:errors]
    assert_empty result[:successes]
    refute_hydro_messages(schema: "github.v1.RepositoryBulkInvite")
  end

  test "does not run for repositories with rate limits exceeded" do
    new_repo = create(:repository, owner: @owner)
    new_invitee = create(:user, login: "invite2", email: "invite2@me.github")
    new_repo_invitation = create(
      :repository_invitation,
      repository: new_repo,
      inviter: @owner,
      invitee: new_invitee,
      permissions: :write
    )
    RepositoryInvitation.any_instance.stubs(:rate_limit_not_exceeded?).returns(false)
    result = RepositoryBulkInviteJob.perform_now(@owner, [@pending_repo_invitation.id, @expired_repo_invitation.id, new_repo_invitation.id])

    assert_equal 3, RepositoryInvitation.where(id: [@pending_repo_invitation.id, @expired_repo_invitation.id, new_repo_invitation.id]).count
    assert_empty result[:successes]
    assert_empty result[:errors]
    assert_dogstats_increment(3, "rate_limited", tags: ["job:repository_bulk_invite_job"])
    refute_hydro_messages(schema: "github.v1.RepositoryBulkInvite")
  end

  context "log_inactionable_invites" do
    test "logs repo exceeded rate limit" do
      RepositoryInvitation.any_instance.stubs(:rate_limit_not_exceeded?).returns(false)

      expected_log = {
        "Body" => "Rate limit exceeded for this repository",
        "code.namespace" => "RepositoryBulkInviteJob",
        "code.function" => "repo_rate_limit_ok",
        "gh.actor.id" => @owner.id,
        "gh.invitee.id" => @pending_repo_invitation.invitee.id,
        "gh.repo.id" => @pending_repo_invitation.repository.id
      }

      assert_logged **expected_log do
        result = RepositoryBulkInviteJob.perform_now(@owner, [@pending_repo_invitation.id])
      end
    end

    test "logs invite_to_repo error" do
      org = create(:business_plus_organization)
      org.disallow_members_can_invite_outside_collaborators(actor: org, force: true)

      oc = create(:user, login: "outside-collaborator")
      oc1 = create(:user, login: "outside-collaborator-1", email: "outside-collaborator-1@github.com")

      repo_private = create(:private_repository, :minimal, owner: org)
      repo_private.add_member(oc)
      repo_private_invitation = create(
        :repository_invitation,
        repository: repo_private,
        inviter: oc,
        invitee: oc1,
        permissions: :write
      )

      expected_log = {
        "Body" => GitHub.enterprise? ? "Only organization owners can add outside collaborators" : "Only organization owners can invite outside collaborators",
        "code.namespace" => "RepositoryBulkInviteJob",
        "code.function" => "add_to_repo_hash",
        "gh.actor.id" => oc.id,
        "gh.invitee.id" => oc1.id,
        "gh.repo.id" => repo_private.id,
        "gh.org.id" => org.id,
      }

      assert_logged **expected_log do
        result = RepositoryBulkInviteJob.perform_now(oc, [repo_private_invitation.id], org.id)
      end
    end

    test "logs invite_to_repo_by_email error" do
      org = create(:business_plus_organization)
      org.disallow_members_can_invite_outside_collaborators(actor: org, force: true)

      oc = create(:user, login: "outside-collaborator")
      oc1 = create(:user, login: "outside-collaborator-1", email: "outside-collaborator-1@github.com")

      repo_private = create(:private_repository, :minimal, owner: org)
      repo_private.add_member(oc)
      repo_private_invitation = create(
        :repository_invitation,
        repository: repo_private,
        inviter: oc,
        invitee: nil,
        email: oc1.email,
        permissions: :write
      )

      expected_log = {
        "Body" => GitHub.enterprise? ? "Only organization owners can add outside collaborators" : "Only organization owners can invite outside collaborators",
        "code.namespace" => "RepositoryBulkInviteJob",
        "code.function" => "add_to_repo_hash",
        "gh.actor.id" => oc.id,
        "gh.repo.id" => repo_private.id,
        "gh.org.id" => org.id,
      }

      assert_logged **expected_log do
        result = RepositoryBulkInviteJob.perform_now(oc, [repo_private_invitation.id], org.id)
      end
    end
  end
end
