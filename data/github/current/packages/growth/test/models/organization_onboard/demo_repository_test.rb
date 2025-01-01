# typed: true
# frozen_string_literal: true

require "test_helper"

module OrganizationOnboard
  class DemoRepositoryTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @organization = create(:organization, admin: @user)
      make_trusted_oauth_apps_owner
      create(:launch_integration)
    end

    test "is deleted with repository" do
      GitHub.flipper[:background_destroy_inverse_enqueue].enable

      org_repo = create(:repository, owner: @organization)
      demo_repo = create(:demo_repository, organization: @organization, repository: org_repo)

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        org_repo.remove(@user, synchronous: true)
      end

      refute OrganizationOnboard::DemoRepository.exists?(demo_repo.id)
    end

    context ".repository_for" do
      test "returns the repository when DemoRepository exists for the organization" do
        repo = OrganizationOnboard::DemoRepository.new(organization: @organization).setup(@user)&.repository

        assert_equal repo, DemoRepository.repository_for(@organization)
      end

      # This is the old behavior we used to create the demo repository. This test will be removed once we remove the old behavior.
      test "returns the repository when DemoRepository does not exist but there is a repo named demo-repository and created_for_demo_by_gh property set" do
        repo = create(:repository, owner: @organization, created_for_demo_by_gh: true, name: DemoRepository::DEFAULT_NAME)

        assert_equal repo, DemoRepository.repository_for(@organization)
      end

      test "returns nil if organization does not have the demo repo" do
        create(:repository, owner: @organization, created_for_demo_by_gh: true, name: "another-repo")

        assert_nil DemoRepository.repository_for(@organization)
      end

      # This is the old behavior we used to create the demo repository. This test will be removed once we remove the old behavior.
      test "returns nil when DemoRepository does not exist and organization has an old demo-repository but it wasn't created by GitHub" do
        create(:repository, owner: @organization, name: DemoRepository::DEFAULT_NAME)

        assert_nil DemoRepository.repository_for(@organization)
      end
    end

    context "#setup" do
      test "creates the demo repository" do
        assert_difference -> { Repository.count }, 1 do
          result = OrganizationOnboard::DemoRepository.new(organization: @organization).setup(@user)

          refute_nil result
          repository = T.must(result).repository

          expected_repo_attributes = {
            "id" => repository.id,
            "name" => "demo-repository",
            "owner_id" => @organization.id,
            "parent_id" => nil,
            "sandbox" => nil,
            "public" => false,
            "description" => "A code repository designed to show the best GitHub has to offer.",
            "public_push" => nil,
            "locked" => false,
          }

          assert_equal(expected_repo_attributes.values, repository.attributes.values_at(*expected_repo_attributes.keys))
          assert_demo_repository(repository)
        end
      end

      test "creates demo if the org has space in its name" do
        organization = create(:organization, name: "Org-Name-With-Space")
        organization.update(profile_name: "Org Name With Space")

        assert_difference -> { Repository.count }, 1 do
          result = OrganizationOnboard::DemoRepository.new(organization: organization).setup(@user)

          refute_nil result
          repository = T.must(result).repository

          assert_demo_repository(repository)

          actions_branch_oid = repository.heads.find_or_build(::OrganizationOnboard::DemoRepository::ACTIONS_WORKFLOW_BRANCH_NAME)
                                .target_oid
          workflow_branch_commit = repository.commits.history(actions_branch_oid).first
          new_readme_content = workflow_branch_commit.diff.entries_hash["entries"][0].text

          assert_match /Org-Name-With-Space/, new_readme_content
        end
      end

      test "generates a random name if demo-repository already exists" do
        create(:repository, owner: @organization, name: DemoRepository::DEFAULT_NAME)

        assert_difference -> { Repository.count }, 1 do
          repo = OrganizationOnboard::DemoRepository.new(organization: @organization).setup(@user)&.repository

          assert_demo_repository(repo)
          refute_equal(DemoRepository::DEFAULT_NAME, repo.name)
        end
      end

      test "does not create the demo repository if it already exists" do
        OrganizationOnboard::DemoRepository.new(organization: @organization).setup(@user)

        assert_no_difference -> { Repository.count } do
          OrganizationOnboard::DemoRepository.new(organization: @organization).setup(@user)
        end
      end
    end

    private

    def assert_demo_repository(repository)
      assert_equal 1, repository.commits.history(repository.default_oid).size
      directory = repository.directory(repository.default_oid)
      assert_equal([".github", "README.md", "index.html",  "package.json"], directory.items.map { |item| item[:content].info["name"] })

      actions_branch_oid = repository.heads.find_or_build(::OrganizationOnboard::DemoRepository::ACTIONS_WORKFLOW_BRANCH_NAME)
                                    .target_oid
      actions_branch_root_directory = repository.directory(actions_branch_oid)
      assert_equal([".github", "README.md", "index.html",  "package.json"], actions_branch_root_directory.items.map do |item|
        item[:content].info["name"]
      end)

      actions_branch_config_directory = repository.directory(actions_branch_oid, ".github")
      assert_equal(["workflows"], actions_branch_config_directory.items.map do |item|
        item[:content].info["name"]
      end)

      assert_equal 2, repository.commits.history(actions_branch_oid).size

      workflow_branch_commit = repository.commits.history(actions_branch_oid).first
      assert_equal "Add workflow badges to README", workflow_branch_commit.message
      assert_equal(["README.md"], workflow_branch_commit.diff.to_tree.nodes.map do |item|
        item.first
      end)

      actions_branch_workflow_directory = repository.directory(actions_branch_oid, ".github/workflows")
      assert_equal(["auto-assign.yml", "proof-html.yml"], actions_branch_workflow_directory.items.map do |item|
        item[:content].info["name"]
      end)
    end
  end
end unless GitHub.enterprise?
