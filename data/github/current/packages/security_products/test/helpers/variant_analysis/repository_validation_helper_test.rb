# typed: true
# frozen_string_literal: true

require "test_helper"

module VariantAnalysis
  class RepositoryValidationHelperTest < GitHub::TestCase
    fixtures do
      @user = create(:user)

      @language = "ruby"

      @public_controller_repo = create(:public_repository)
      @private_controller_repo = create(:private_repository)

      @public_repo1 = create(:public_repository)
      @public_repo2 = create(:public_repository)

      @private_repo1 = create(:private_repository)
      @private_repo2 = create(:private_repository)

      @no_codeql_db_repo = create(:repository)
      @codeql_db_repo1 = create(:repository)
      @codeql_db_repo2 = create(:repository)
      add_codeql_db(@codeql_db_repo1)
      add_codeql_db(@codeql_db_repo2)
    end

    def setup
      @helper = FakeHelper.new.extend(RepositoryValidationHelper)
    end

    def add_codeql_db(repo)
      CodeqlDatabase.create!(
        repository: repo, uploader: repo.owner, state: :uploaded, size: 1234,
        name: "ruby.zip", content_type: "application/zip", language: "ruby"
      )
    end

    context "repository validation" do
      test "identifies existing repositories" do
        repo_ids = [@public_repo1.id, @private_repo1.id, "fake-repo-id-1", "fake-repo-id-2"]

        valid_repo_ids, not_found_repo_ids = @helper.partition_on_existing_repos(repo_ids)

        assert_equal [@public_repo1.id, @private_repo1.id], valid_repo_ids
        assert_equal %w[fake-repo-id-1 fake-repo-id-2], not_found_repo_ids
      end

      test "identifies private repos against public controller repo" do
        repos = [@public_repo1, @private_repo1]
        repo_ids = repos.map(&:id)

        valid_repo_ids, privacy_mismatch_repo_ids = @helper.partition_on_controller_repo_privacy(repo_ids, @public_controller_repo)

        assert_equal [@public_repo1.id], valid_repo_ids
        assert_equal [@private_repo1.id], privacy_mismatch_repo_ids
      end

      test "does not exclude private repos against private controller repo" do
        repos = [@public_repo1, @private_repo1]
        repo_ids = repos.map(&:id)

        valid_repo_ids, privacy_mismatch_repo_ids = @helper.partition_on_controller_repo_privacy(repo_ids, @private_controller_repo)

        assert_equal [@public_repo1.id, @private_repo1.id].to_set, valid_repo_ids.to_set
        assert_empty privacy_mismatch_repo_ids
      end

      test "identifies repos with no codeql db" do
        repos = [@codeql_db_repo1, @codeql_db_repo2, @no_codeql_db_repo]
        repo_ids = repos.map(&:id)

        valid_repo_ids, no_codeql_db_repo_ids = @helper.partition_on_db_availability(repo_ids, @language)

        assert_equal [@no_codeql_db_repo.id], no_codeql_db_repo_ids
        assert_equal [@codeql_db_repo1.id, @codeql_db_repo2.id].to_set, valid_repo_ids.to_set
      end

      test "identifies over-limit repos" do
        repo1 = create(:repository)
        repo1.update(pushed_at: 1.day.ago)
        repo2 = create(:repository)
        repo2.update(pushed_at: 2.days.ago)
        repo3 = create(:repository)
        repo3.update(pushed_at: 3.days.ago)
        repo4 = create(:repository)
        repo4.update(pushed_at: 4.days.ago)
        repo_ids = [repo1.id, repo2.id, repo3.id, repo4.id]

        RepositoryValidationHelper.stub_const(:REPOSITORIES_COUNT_LIMIT, 2) do
          valid_repo_ids, over_limit_repo_ids = @helper.partition_on_max_repos(repo_ids)

          assert_equal [repo1.id, repo2.id].to_set, valid_repo_ids.to_set
          assert_equal [repo3.id, repo4.id].to_set, over_limit_repo_ids.to_set
        end
      end
    end
  end
end
