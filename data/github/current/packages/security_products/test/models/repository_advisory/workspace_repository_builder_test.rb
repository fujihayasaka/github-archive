# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryWorkspaceRepositoryBuilderTest < GitHub::TestCase
  fixtures do
    @repo = create(:org_owned_repository)
    example_repo :simple, @repo

    @owner = @repo.owner

    @author = create(:user)

    @advisory = create(:repository_advisory, repository: @repo, author: @author)
  end

  setup do
    GitHub.context.push(actor_id: @owner.id)
  end

  test "builds a new repo that is a clone of the origin repo" do
    workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @author).tap(&:save!)

    refute_predicate workspace_repo, :public?
    assert_equal workspace_repo.parent_advisory.repository, @repo
  end

  test "builds a new repo when org owned and repository projects are disabled for the org" do
    @owner.disable_repository_projects(actor: @author)
    create(:repository_advisory, :with_workspace, repository: @repo, author: @author)
  end

  test "enqueues a job to clone the origin repo" do
    assert_enqueued_with(job: RepositoryCloneJob) do
      RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @author).tap(&:save!)
    end
  end

  test "copies repository license" do
    mit_license = License.find("mit")
    @repo.create_repository_license(license_id: mit_license.id)

    workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @author).tap(&:save!)
    assert_equal workspace_repo.repository_license.license_id, mit_license.id
  end

  test "raises an error if actor is nil" do
    assert_raises(ArgumentError) do
      RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, nil)
    end
  end

  test "returns repository with lowercase GHSA-ID-based name" do
    workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @author)

    assert_includes workspace_repo.name, @advisory.ghsa_id.downcase
    assert_includes workspace_repo.name, @repo.name
  end

  test "truncates the original name if needed to appease length validation" do
    # Repository names must be 100 characters or fewer.
    @repo.update!(name: "x" * 100)

    workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @author)

    assert_equal 100, workspace_repo.name.length
    assert_includes workspace_repo.name, @advisory.ghsa_id.downcase
  end

  test "if feature flagged, set restorable to false on creation" do
    GitHub.flipper[:advisory_db_unrestorable_repositories].enable(@author)
    workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @author).tap(&:save!)
    refute_predicate workspace_repo, :restorable?
  end
end
