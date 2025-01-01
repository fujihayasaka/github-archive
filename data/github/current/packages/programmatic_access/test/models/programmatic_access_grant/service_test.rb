# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class ProgrammaticAccessGrant::ServiceTest < GitHub::TestCase
  include PermissionsHelper
  include ApiProgrammaticGrantHelpers

  fixtures do
    @user = create(:user)
    @admin = create(:user)
    @org = create(:organization, admin: @admin)
    @member = create(:user)

    @org.add_member(@member)
    @org.update_default_repository_permission(:none, actor: @admin)

    @grant = make_user_programmatic_access_with_grant(
      requester: @member,
      target: @org,
      permissions: { "metadata" => :read },
      repositories: [create(:repository, owner: @org)],
      repository_selection: :subset
    ).grant
    @access = @grant.user_programmatic_access
  end

  context "revoke" do
    test "actor must be able to revoke grants for the target" do
      grant = ProgrammaticAccessGrant::Service.revoke(@grant, @user)

      assert grant
      assert_predicate grant, :persisted?
      assert_includes grant.errors[:actor], "must have sufficient permissions to revoke this grant"
    end

    test "actor must be provided" do
      grant = ProgrammaticAccessGrant::Service.revoke(@grant, nil)

      assert grant
      assert_predicate grant, :persisted?
      assert_includes grant.errors[:actor], "must exist"
    end

    test "destroys grant upon success" do
      assert_difference("OrganizationProgrammaticAccessGrant.count", -1) do
        perform_enqueued_jobs(only: [ClearAbilitiesJob, DestroyDependentRecordsJob]) do
          ProgrammaticAccessGrant::Service.revoke(@grant, @admin)
        end
      end

      assert_equal 0, Permission.where(actor_id: @grant.ability_id, actor_type: @grant.ability_type).count
    end

    test "notifies access owner about the revoke" do
      UserProgrammaticAccess
        .expects(:notify_owner)
        .with(
          about: :revoked,
          accesses: [@access],
          owner: @access.owner,
          target: @org
        )

      grant = ProgrammaticAccessGrant::Service.revoke(@grant, @admin)
      assert_predicate grant.errors, :empty?
    end

    test "does not notify access owner about the revoke when skip_revoke_notification is true" do
      UserProgrammaticAccess.expects(:notify_owner).never

      grant = ProgrammaticAccessGrant::Service.revoke(@grant, @user, skip_revoke_notification: true)
      assert_predicate grant.errors, :any?
    end

    test "does not notify access owner about the revoke on failures" do
      UserProgrammaticAccess.expects(:notify_owner).never

      grant = ProgrammaticAccessGrant::Service.revoke(@grant, @user)
      assert_predicate grant.errors, :any?
    end
  end

  context "bulk_revoke" do
    test "actor must be able to revoke grants for the target" do
      result = ProgrammaticAccessGrant::Service.bulk_revoke([@grant.id], @user, @org)

      assert_includes result.errors[:actor], "must have sufficient permissions to revoke grants"
    end

    test "actor must be provided" do
      result = ProgrammaticAccessGrant::Service.bulk_revoke([@grant.id], nil, @org)

      assert_includes result.errors[:actor], "must exist"
    end

    test "target must be provided" do
      result = ProgrammaticAccessGrant::Service.bulk_revoke([@grant.id], @admin, nil)

      assert_includes result.errors[:target], "must exist"
    end

    test "grant_ids must be provided" do
      result = ProgrammaticAccessGrant::Service.bulk_revoke(nil, @admin, @org)

      assert_includes result.errors[:grant_ids], "must exist"
    end

    test "grant_ids must be 1 or more" do
      result = ProgrammaticAccessGrant::Service.bulk_revoke(nil, @admin, @org)

      assert_includes result.errors[:grant_ids], "must not be empty"
    end

    test "grant_ids must belong to target" do
      other_org = create(:organization)
      grant = make_user_programmatic_access_with_grant(
        requester: other_org.admin,
        target: other_org,
        permissions: { "metadata" => :read },
        repositories: [create(:repository, owner: other_org)],
        repository_selection: :subset
      ).grant
      result = ProgrammaticAccessGrant::Service.bulk_revoke([grant.id], @admin, @org)

      assert_includes result.errors[:grants], "one or more grants do not belong to the target."
    end

    test "returns early if there are errors" do
      result = ProgrammaticAccessGrant::Service.bulk_revoke(
        [@grant.id],
        nil,
        @org
      )

      refute @grant.destroyed?
    end

    test "queues background job to revoke tokens in bulk" do
      grant_ids = [@grant.id]
      expected_args = { grant_ids: grant_ids, actor: @admin, target: @org }
      BulkRevokeProgrammaticAccessGrantsJob.expects(:perform_later).with(**expected_args)
      ProgrammaticAccessGrant::Service.bulk_revoke(grant_ids, @admin, @org)
    end
  end
end
