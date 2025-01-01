# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPreferredFilesDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @org_global_repo = create(:repository, owner: @org, name: Repository::GLOBAL_HEALTH_FILES_NAME)
    @org_local_files_repo = create(:repository, owner: @org)
    @citation_on_branch_repo = create(:repository, owner: @org)
  end

  setup do
    example_repo :community_files, @org_global_repo
    example_repo :community_files, @org_local_files_repo
    example_repo :citation_on_branch, @citation_on_branch_repo
  end

  context "#async_global_health_files_repo" do
    test "returns global health files repo when it exists for the repository" do
      assert_equal @org_global_repo, @org_local_files_repo.async_global_health_files_repo.sync
    end

    test "returns nil when no global health file repo exists for the repository" do
      assert_nil create(:repository).async_global_health_files_repo.sync
    end

    test "returns nil for a global health files repo itself" do
      assert_nil @org_global_repo.async_global_health_files_repo.sync
    end
  end

  context "#global_health_files_repo" do
    test "returns global health files repo when it exists for the repository" do
      assert_equal @org_global_repo, @org_local_files_repo.global_health_files_repo
    end

    test "returns nil when no global health file repo exists for the repository" do
      assert_nil create(:repository).global_health_files_repo
    end

    test "returns nil for a global health files repo itself" do
      assert_nil @org_global_repo.global_health_files_repo
    end

    test "can be efficiently batch loaded for many repos" do
      repo = create(:repository)
      repos = [@org_local_files_repo, repo, @org_global_repo]

      assert_query_count_per_table({ repositories: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method(repos, :global_health_files_repo)
      end

      assert_query_count(0) do
        assert_equal @org_global_repo, @org_local_files_repo.global_health_files_repo
        assert_nil repo.global_health_files_repo
        assert_nil @org_global_repo.global_health_files_repo
      end
    end
  end

  context "repository_preferred_files association" do
    test "destroys preferred_files records when repo is destroyed" do
      preferred_file = create(:repository_preferred_file, repository: @org_global_repo)

      assert_difference(-> { RepositoryPreferredFile.count }, -1) do
        @org_global_repo.destroy!
      end

      refute RepositoryPreferredFile.exists?(preferred_file.id)
    end
  end

  context "#async_global_preferred_file" do
    test "returns global preferred file" do
      file = @org_local_files_repo.async_global_preferred_file(:code_of_conduct).sync
      assert_equal @org_global_repo, file.repository
    end

    test "returns nil if global file does not exist" do
      assert_nil @org_local_files_repo.async_global_preferred_file(:funding).sync
    end

    test "returns nil if type is not a global file" do
      @org_global_repo.default_branch_ref.append_commit(
        { message: "Add CODEOWNERS", committer: @org.admin }, @org.admin
      ) do |files|
        files.add("CODEOWNERS", "* @defunkt")
      end

      assert @org_global_repo.preferred_file(:codeowners)
      assert_nil @org_local_files_repo.async_global_preferred_file(:codeowners).sync
    end

    test "returns nil if repository is already global repo" do
      assert_nil @org_global_repo.async_global_preferred_file(:code_of_conduct).sync
    end
  end

  context "#preferred_file" do
    test "returns preferred file on specific branch" do
      tree_name = @citation_on_branch_repo.heads.first.name
      file = @citation_on_branch_repo.preferred_file(:citation, tree_name: tree_name)
      assert_equal @citation_on_branch_repo, file.repository
    end

    test "returns nil when preferred file not on specific branch" do
      default_branch = @citation_on_branch_repo.default_branch
      assert_nil @citation_on_branch_repo.preferred_file(:citation, tree_name: default_branch)
    end
  end
end
