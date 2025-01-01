# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class ProgrammaticAccess::AccessibleRepositoriesDependencyTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include PermissionsHelper

  fixtures do
    @subject = create(:user_programmatic_access)
    @owner = @subject.owner

    @repo1 = create(:repository, :minimal, owner: @owner)
    @repo2 = create(:repository, :minimal, owner: @owner)

    @grant = make_programmatic_access_grant(
      permissions: { "metadata" => :read },
      access: @subject, target: @owner,
      repositories: [@repo1], repository_selection: :subset,
    )
  end

  context "#accessible_repository_ids" do
    test "only returns repos that are accessible to the grant" do
      assert_actor_and_subject_granted_in_permissions_table(
        actor: @grant, subject: @repo1.resources.metadata, action: :read
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: @grant, subject: @repo2.resources.metadata, action: :read
      )

      ids = @subject.accessible_repository_ids(repository_ids: [@repo1.id, @repo2.id])
      assert_same_elements [@repo1.id], ids
    end

    test "only returns repos that are accessible to the organization grant" do
      subject = create(:user_programmatic_access, owner: @owner)

      org = create(:organization, admin: @owner)
      org_repo1 = create(:repository, :minimal, owner: org)
      org_repo2 = create(:repository, :minimal, owner: org)

      org_grant = make_programmatic_access_grant(
        permissions: { "metadata" => :read },
        access: subject, target: org,
        repositories: [org_repo1], repository_selection: :subset,
      )

      assert_actor_and_subject_granted_in_permissions_table(
        actor: org_grant, subject: org_repo1.resources.metadata, action: :read
      )

      refute_actor_and_subject_granted_in_permissions_table(
        actor: org_grant, subject: org_repo2.resources.metadata, action: :read
      )

      ids = subject.accessible_repository_ids(repository_ids: [org_repo1.id, org_repo2.id])
      assert_same_elements [org_repo1.id], ids
    end

    test "can filter by resource type" do
      assert_empty @subject.accessible_repository_ids(repository_ids: [@repo1.id, @repo2.id], resource: "issues")
    end

    test "returns an empty result if the grant is not installed on the given target" do
      other_target = create(:user)
      assert_empty @subject.accessible_repository_ids(repository_ids: [@repo1.id, @repo2.id], target: other_target)
    end
  end
end
