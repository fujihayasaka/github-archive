# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexRepositorySuggesterTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @staff = create(:staff_admin_user)
    @org.add_member(@staff)
    @org_viewer = create(:user).tap { |u| @org.add_member(u) }
    @org_memex = create(:memex_project, owner: @org)
    @org_repositories = create_list(:repository, 5, owner: @org, public: false)
    @org_memex_items = create_memex_items(@org_repositories, @org_memex)

    @diff_org = create(:organization)
    @diff_org_repositories = create_list(:repository, 5, owner: @diff_org)
    @diff_org_memex_items = create_memex_items(@diff_org_repositories, @org_memex)

    @owner = create(:user)
    @viewer = create(:user)
    @user_memex = create(:memex_project, owner: @owner)
    @user_repositories = create_list(:repository, 5, owner: @owner)
    @user_memex_items = create_memex_items(@user_repositories, @user_memex)

    @diff_owner = create(:user)
    @diff_owner_repositories = create_list(:repository, 5, owner: @diff_owner)
    @diff_owner_memex_items = create_memex_items(@diff_owner_repositories, @user_memex)

    @user_owner_of_other_orgs = create(:verified_user)
    @org.add_member(@user_owner_of_other_orgs)

    # creating additional organizations that a user has access to, so we can explore how multiple orgs behave
    # when the user is an admin of different organizations
    @another_organization = create(:organization, admin: @user_owner_of_other_orgs, name: "another-organization")
    @another_organization_repo = create(:private_repository, owner: @another_organization)
    @also_another_organization = create(:organization, admin: @user_owner_of_other_orgs, name: "also-another-organization")
    @also_another_organization_repo = create(:private_repository, owner: @also_another_organization)

    # creating a separate project with items belonging to other organizations so we can verify that organization
    # repostiories are still visible as suggestions
    @org_memex_with_items_from_other_orgs = create(:memex_project, owner: @org)
    @org_memex_items_from_other_orgs = create_memex_items([@another_organization_repo, @also_another_organization_repo], @org_memex_with_items_from_other_orgs)
  end

  setup do
    @org_suggester = MemexRepositorySuggester.new(
      viewer: @org_viewer,
      owner: @org,
      memex_project: @org_memex,
    )

    @user_suggester = MemexRepositorySuggester.new(
      viewer: @viewer,
      owner: @owner,
      memex_project: @user_memex,
    )
  end

  # This creates a total of 15 memex items: 1 for the first repo, 2 for the
  # second, and so on until 5 for the fifth repo.
  def create_memex_items(repositories, memex)
    repositories.each_with_index.reduce([]) do |items, (repo, index)|
      items += create_list(:issue, index + 1, repository: repo).map do |issue|
        create(:memex_project_item, memex_project: memex, content: issue)
      end
    end
  end

  context "#repositories" do
    test "does not include draft issues which have no repository_id" do
      content = create(:draft_issue)
      draft_memex_item = create(:memex_project_item, memex_project: @org_memex, content: content, repository: nil)

      suggestions = MemexRepositorySuggester.new(
        viewer: @org_viewer,
        owner: @org,
        memex_project: @org_memex,
      ).repositories

      assert_same_elements @org_repositories.map(&:memex_suggestion_hash), suggestions
    end
  end

  context "#repositories when owner is an organization" do
    test "suggests repositories already referenced in the memex table in order of frequency" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      assert_equal @org_repositories.reverse.map(&:memex_suggestion_hash), @org_suggester.repositories
      assert_equal 1, GitHub.dogstats.distributions("memex_repository_suggester.repositories.dist").length
    end

    test "augments referenced repositories with non-archived repositories in the org" do
      org = create(:organization)
      org_viewer = create(:user).tap { |u| org.add_member(u) }
      org_memex = create(:memex_project, owner: org)
      org_repositories = create_list(:repository, 3, owner: org, public: false)
      org_memex_items = create_memex_items(org_repositories, org_memex)
      other_org_repos = create_list(:repository, 5, owner: org)

      suggestions = MemexRepositorySuggester.new(
        viewer: org_viewer,
        owner: org,
        memex_project: org_memex,
      ).repositories

      # Make sure repos already referenced in the memex table come first.
      assert_equal org_repositories[0...3].reverse.map(&:memex_suggestion_hash), suggestions[0...3]

      # Make sure that we pad the list of suggestions with other repos.
      assert_equal MemexRepositorySuggester::SUGGESTED_REPOSITORIES_LIMIT, suggestions.length
    end

    test "does not suggest repositories of memex items from different owner" do
      suggestions = MemexRepositorySuggester.new(
        viewer: @org_viewer,
        owner: @org,
        memex_project: @org_memex,
      ).repositories

      assert_equal @org_repositories.reverse.map(&:memex_suggestion_hash), suggestions
    end

    test "we don't make more SQL queries than expected" do
      GitHub.flipper[:repo_dependency_team_iterator].enable
      GitHub.flipper[:contribution_fetchers].disable(@org_viewer)

      many_org_repositories = create_list(:repository, 10, owner: @org)
      many_org_memex_items = create_memex_items(many_org_repositories, @org_memex)

      assert_query_count(33, ignore_feature_flags: true) do
        MemexRepositorySuggester.new(
          viewer: @org_viewer,
          owner: @org,
          memex_project: @org_memex,
        ).repositories
      end
    end

    test "does not suggest repositories of memex items that are not visible to viewer" do
      @org.update_default_repository_permission(:none, actor: @org.admins.first)
      org_private_repositories = create_list(:repository, 5, owner: @org, private: true)
      org_private_items = create_memex_items(org_private_repositories, @org_memex)

      suggestions = MemexRepositorySuggester.new(
        viewer: @org_viewer,
        owner: @org,
        memex_project: @org_memex,
      ).repositories

      assert_same_elements @org_repositories.map(&:memex_suggestion_hash), suggestions
    end

    test "padding repositories with suggested repositories does not replace more frequently appearing private repositories within memex items that are visible to viewer" do
      @org.update_default_repository_permission(:read, actor: @org.admins.first)
      org_memex = create(:memex_project, owner: @org)
      first_org_private_repository = create(:private_repository, owner: @org, name: "first-private")
      second_org_private_repository = create(:private_repository, owner: @org, name: "second-private")
      third_org_private_repository = create(:private_repository, owner: @org, name: "third-private")
      first_org_public_repository = create(:public_repository, owner: @org, name: "first-public")
      second_org_public_repository = create(:public_repository, owner: @org, name: "second-public")

      # Need first_org_private_repository to appear first, create 4 issues in @org_memex
      create_list(:issue, 4, repository: first_org_private_repository).map do |issue|
        create(:memex_project_item, memex_project: org_memex, content: issue)
      end

      # Need second_org_private_repository to appear second, create 3 issues in org_memex
      create_list(:issue, 3, repository: second_org_private_repository).map do |issue|
        create(:memex_project_item, memex_project: org_memex, content: issue)
      end

      # Need first_org_public_repository to appear third, create 2 issues in org_memex
      create_list(:issue, 2, repository: first_org_public_repository).map do |issue|
        create(:memex_project_item, memex_project: org_memex, content: issue)
      end

      # Need third_org_private_repository to appear fourth, create 1 issue in org_memex
      third_org_private_repo_issue = create(:issue, repository: third_org_private_repository)
      create(:memex_project_item, memex_project: org_memex, content: third_org_private_repo_issue)

      MemexRepositorySuggester.stub_const(:SUGGESTED_REPOSITORIES_LIMIT, 5)  do
        suggestions = MemexRepositorySuggester.new(
          viewer: @org_viewer,
          owner: @org,
          memex_project: org_memex,
        ).repositories
        expected_repositories = [
          first_org_private_repository,
          second_org_private_repository,
          first_org_public_repository,
          third_org_private_repository,
        ]

        assert_equal 5, suggestions.length, "expected suggestions to be padded until suggested limit"
        assert_same_elements expected_repositories.map(&:memex_suggestion_hash), suggestions.take(expected_repositories.length), "expected suggestions to be in order of frequency"
      end
    end

    test "does not suggest repositories of memex items that are not visible to viewer even if viewer is staff" do
      @org.update_default_repository_permission(:none, actor: @org.admins.first)
      org_private_repositories = create_list(:repository, 5, owner: @org, private: true)
      org_private_items = create_memex_items(org_private_repositories, @org_memex)

      suggestions = MemexRepositorySuggester.new(
        viewer: @staff,
        owner: @org,
        memex_project: @org_memex,
      ).repositories

      assert_same_elements @org_repositories.map(&:memex_suggestion_hash), suggestions
    end

    test "suggest only repos initiated with with_issue_types" do
      suggestions = MemexRepositorySuggester.new(
        viewer: @org_viewer,
        owner: @org,
        memex_project: @org_memex,
        with_issue_types: true
      ).repositories

      assert_same_elements @org_repositories.map(&:memex_suggestion_hash), suggestions
    end

    test "suggest only repos with milestone if initiated with a milestone" do
      milestone_title = "v1.0"
      repositories_with_milestone = create_list(:repository, 2, owner: @org)
      repositories_with_milestone.each do |repository|
        # create two different milestones with the same title
        create(:milestone, repository: repository, title: milestone_title)
      end
      repositories_with_different_milestone = create_list(:repository, 2, owner: @org)
      repositories_with_different_milestone.each do |repository|
        # create two different milestones with the same title
        create(:milestone, repository: repository)
      end

      suggestions = MemexRepositorySuggester.new(
        viewer: @org_viewer,
        owner: @org,
        memex_project: @org_memex,
        milestone: milestone_title
      ).repositories

      assert_same_elements repositories_with_milestone.map(&:memex_suggestion_hash), suggestions
    end

    context "blank slate" do
      test "suggests recently interacted repositories first" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        org_empty_memex = create(:memex_project, owner: @org)

        repo = create(:repository, owner: @org)
        suggester = MemexRepositorySuggester.new(
          viewer: @org_viewer,
          owner: @org,
          memex_project: org_empty_memex,
        )
        suggestions = suggester.repositories
        assert_equal suggestions.first, repo.memex_suggestion_hash

        assert_equal 1, GitHub.dogstats.distributions("memex_repository_suggester.repositories.dist").length
      end
    end

  end

  context "#repositories when owner is a user" do
    test "suggests repositories already referenced in the memex table in order of frequency" do
      assert_equal @user_repositories.reverse.map(&:memex_suggestion_hash), @user_suggester.repositories
    end

    test "augments referenced repositories with non-archived repositories from the owner" do
      owner = create(:user)
      owner_repositories = create_list(:repository, 3, owner: owner)
      memex = create(:memex_project, owner: owner)
      user_memex_items = create_memex_items(owner_repositories, memex)
      other_owner_repos = create_list(:repository, 5, owner: owner)

      suggestions = MemexRepositorySuggester.new(
        viewer: @viewer,
        owner: owner,
        memex_project: memex,
      ).repositories

      # Make sure repos already referenced in the memex table come first.
      assert_equal owner_repositories[0...3].reverse.map(&:memex_suggestion_hash), suggestions[0...3]

      # Make sure that we pad the list of suggestions with other repos.
      assert_equal MemexRepositorySuggester::SUGGESTED_REPOSITORIES_LIMIT, suggestions.length
    end

    test "hides private repositories for external viewer" do
      other_owner_repos = create_list(:repository, 5, owner: @owner, private: true)

      suggestions = MemexRepositorySuggester.new(
        viewer: @viewer,
        owner: @owner,
        memex_project: @user_memex,
      ).repositories

      assert_same_elements @user_repositories.map(&:memex_suggestion_hash), suggestions
    end

    test "does not suggest repositories of memex items from different owner" do
      suggestions = MemexRepositorySuggester.new(
        viewer: @viewer,
        owner: @owner,
        memex_project: @user_memex,
      ).repositories

      assert_equal @user_repositories.reverse.map(&:memex_suggestion_hash), suggestions
    end

    test "does not suggest repositories of memex items that are not visible to viewer" do
      private_repos = create_list(:private_repository, 5, owner: @owner)
      private_memex_items = create_memex_items(private_repos, @user_memex)

      suggestions = MemexRepositorySuggester.new(
        viewer: @viewer,
        owner: @owner,
        memex_project: @user_memex,
      ).repositories

      assert_same_elements @user_repositories.map(&:memex_suggestion_hash), suggestions
    end

    test "padding repositories with suggested repositories does not replace more frequently appearing private repositories within memex items that are visible to viewer" do
      user_memex = create(:memex_project, owner: @owner)
      public_repository = create(:repository, owner: @owner)
      private_repository = create(:private_repository, owner: @owner)

      # Need private_repository to appear first, create 3 issues in user_memex
      memex_items = create_list(:issue, 3, repository: private_repository).map do |issue|
        create(:memex_project_item, memex_project: user_memex, content: issue)
      end

      # Need public_repository to appear second, create 2 issues in user_memex
      memex_items += create_list(:issue, 2, repository: public_repository).map do |issue|
        create(:memex_project_item, memex_project: user_memex, content: issue)
      end

      MemexRepositorySuggester.stub_const(:SUGGESTED_REPOSITORIES_LIMIT, 5)  do
        suggestions = MemexRepositorySuggester.new(
          viewer: @owner, # viewer has to be same as owner for user owned, otherwise private repos would be filtered
          owner: @owner,
          memex_project: user_memex,
        ).repositories
        expected_repositories = [
          private_repository,
          public_repository,
        ]

        assert_predicate public_repository, :public?
        refute_predicate private_repository, :public?
        assert_equal 5, suggestions.length, "expected suggestions to be padded until suggested limit"
        assert_same_elements expected_repositories.map(&:memex_suggestion_hash), suggestions.take(expected_repositories.length), "expected first 2 suggestions to be in order of frequency"
      end
    end

    context "#associated_repository_including" do
      test "includes organization repositories when user is an admin of other organizations" do
        suggester = MemexRepositorySuggester.new(
          viewer: @user_owner_of_other_orgs,
          owner: @org,
          memex_project: @org_memex,
        )

        repositories = suggester.repositories

        assert_equal 5, repositories.length
        repositories.each do |repo|
          owner, repo = repo[:nameWithOwner].split "/"
          assert_equal owner, @org.name
        end
      end

      test "includes organization repositories for specified owner when association is indirect admin" do
        # Set default permission to :none
        perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
          @another_organization.update_default_repository_permission(:none, actor: @user_owner_of_other_orgs)
        end

        org_memex = create(:memex_project, owner: @another_organization)

        suggester = MemexRepositorySuggester.new(
          viewer: @user_owner_of_other_orgs,
          owner: @another_organization,
          memex_project: org_memex,
        )

        repositories = suggester.repositories

        assert_equal 1, repositories.length
        assert_equal repositories[0][:nameWithOwner], @another_organization_repo.name_with_owner
      end
    end
  end
end
