# typed: true
# frozen_string_literal: true
require "test_helper"

module VariantAnalysis
  class RepositoryResolutionHelperTest < GitHub::TestCase
    include ConditionalAccess::FilterTestHelper

    fixtures do
      @language = "ruby"

      @owner = create(:user)
      @public_repo1 = create(:public_repository, owner: @owner)
      @public_repo2 = create(:public_repository, owner: @owner)
    end

    setup do
      @helper = FakeHelper.new.extend(RepositoryResolutionHelper)
      @helper.current_user = @owner
      @helper.cap_filter = cap_authorizing_filter
    end

    context "repository resolution helper" do
      context "resolve repositories" do
        test "returns empty if no repository information is given" do
          repositories = []

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: [],
            repository_lists: [],
            repository_owners: []
          )

          assert_empty result[:repo_ids]
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "resolves repository nwos" do
          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: [@public_repo1.nwo, @public_repo2.nwo],
            repository_lists: nil,
            repository_owners: nil
          )

          assert_equal [@public_repo1.id, @public_repo2.id].to_set, result[:repo_ids].to_set
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "resolves repository nwos with different casing" do
          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: [@public_repo1.nwo.upcase, @public_repo2.nwo],
            repository_lists: nil,
            repository_owners: nil
          )

          assert_equal [@public_repo1.id, @public_repo2.id].to_set, result[:repo_ids].to_set
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "returns invalid repository nwos" do
          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: [@public_repo1.nwo, "invalid-nwo"],
            repository_lists: nil,
            repository_owners: nil
          )

          assert_equal [@public_repo1.id], result[:repo_ids]
          assert_equal ["invalid-nwo"], result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "handles very large numbers of NWOs" do
          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: [@public_repo1.nwo] + 5000.times.map { |n| "unknown/repo_#{n}" },
            repository_lists: nil,
            repository_owners: nil
          )

          assert_equal [@public_repo1.id], result[:repo_ids]
          assert_equal 5000, result[:invalid_repo_nwos].length
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "resolves repository list" do
          repository_list = "test-list"
          repository_list_nwos = [@public_repo1.nwo, @public_repo2.nwo]
          VariantAnalysis::CodeScanningRepoLists.stubs(:get_repo_list).returns(repository_list_nwos)

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: nil,
            repository_lists: [repository_list],
            repository_owners: nil
          )

          assert_equal [@public_repo1.id, @public_repo2.id].to_set, result[:repo_ids].to_set
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "returns invalid repository list if it doesn't exist" do
          repository_list = "test-list"
          VariantAnalysis::CodeScanningRepoLists.stubs(:get_repo_list).returns(nil)

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: nil,
            repository_lists: [repository_list],
            repository_owners: nil
          )

          assert_empty result[:repo_ids]
          assert_empty result[:invalid_repo_nwos]
          assert_equal [repository_list], result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "returns invalid repository list if is empty" do
          repository_list = "test-list"
          VariantAnalysis::CodeScanningRepoLists.stubs(:get_repo_list).returns([])

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: nil,
            repository_lists: [repository_list],
            repository_owners: nil
          )

          assert_empty result[:repo_ids]
          assert_empty result[:invalid_repo_nwos]
          assert_equal [repository_list], result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "resolves repository owner" do
          # Repos that have the correct language or already have a CodeQL database for the given language
          create(:language, repository: @public_repo1, language_name: create(:language_name, name: @language))
          create(:codeql_database, repository: @public_repo2, language: @language)

          # Repo with no CodeQL database or associated language
          create(:repository, owner: @owner)

          # Repo with CodeQL database for the wrong language
          repo_with_wrong_db = create(:repository, owner: @owner)
          create(:codeql_database, repository: repo_with_wrong_db, language: "fake-language")

          # Repo with the wrong language
          repo_with_wrong_language = create(:repository, owner: @owner)
          create(:language, repository: repo_with_wrong_language, language_name: create(:language_name, name: "fake-language"))

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: nil,
            repository_lists: nil,
            repository_owners: [@owner.name]
          )

          assert_equal [@public_repo1.id, @public_repo2.id].to_set, result[:repo_ids].to_set
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "returns no repositories for repository owner without repos" do
          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: nil,
            repository_lists: nil,
            repository_owners: [@owner.name]
          )

          assert_empty result[:repo_ids]
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "returns invalid owner" do
          owner_name = "invalid-owner"

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: nil,
            repository_lists: nil,
            repository_owners: [owner_name]
          )

          assert_empty result[:repo_ids]
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_equal [owner_name], result[:invalid_owners]
        end

        test "resolves repository nwos, lists and owners" do
          owner1 = create(:user)
          owner1_repo1 = create(:public_repository, :with_codeql_database, owner: owner1)
          owner1_repo2 = create(:public_repository, :with_codeql_database, owner: owner1)

          owner2 = create(:user)
          owner2_repo1 = create(:public_repository, :with_codeql_database, owner: owner2)
          owner2_repo2 = create(:public_repository, :with_codeql_database, owner: owner2)

          repository_list = "test-list"
          list_owner = create(:user)
          list_repo1 = create(:public_repository, owner: list_owner)
          list_repo2 = create(:public_repository, owner: list_owner)
          VariantAnalysis::CodeScanningRepoLists.stubs(:get_repo_list).returns([list_repo1.nwo, list_repo2.nwo])

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: [@public_repo1.nwo, @public_repo2.nwo],
            repository_lists: [repository_list],
            repository_owners: [owner1.name, owner2.name]
          )

          all_repo_ids = [@public_repo1.id, @public_repo2.id, owner1_repo1.id, owner1_repo2.id, owner2_repo1.id, owner2_repo2.id, list_repo1.id, list_repo2.id]
          assert_equal all_repo_ids.to_set, result[:repo_ids].to_set
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "filters our inaccessible repos from repository_nwos" do
          @accessible_private_repo = create(:private_repository, owner: @owner)
          @inaccessible_repo = create(:private_repository, owner: create(:user))

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: [@public_repo1.nwo, @accessible_private_repo.nwo, @inaccessible_repo.nwo],
            repository_lists: nil,
            repository_owners: nil
          )

          assert_equal [@public_repo1.id, @accessible_private_repo.id].to_set, result[:repo_ids].to_set
          assert_equal [@inaccessible_repo.nwo], result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "fails gracefully if there are no accessible repos" do
          @inaccessible_repo = create(:private_repository, owner: create(:user))

          repository_list = "test-list"
          list_owner = create(:user)
          accessible_repo = create(:public_repository, owner: list_owner)
          inaccessible_repo = create(:private_repository, owner: list_owner)
          VariantAnalysis::CodeScanningRepoLists.stubs(:get_repo_list).returns([accessible_repo.nwo, inaccessible_repo.nwo])

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: [@inaccessible_repo.nwo],
            repository_lists: nil,
            repository_owners: nil
          )

          assert_empty result[:repo_ids]
          assert_equal [@inaccessible_repo.nwo], result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "filters our inaccessible repos from repository_lists" do
          repository_list = "test-list"
          list_owner = create(:user)
          accessible_repo = create(:public_repository, owner: list_owner)
          inaccessible_repo = create(:private_repository, owner: list_owner)
          VariantAnalysis::CodeScanningRepoLists.stubs(:get_repo_list).returns([accessible_repo.nwo, inaccessible_repo.nwo])

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: nil,
            repository_lists: [repository_list],
            repository_owners: nil
          )

          assert_equal [accessible_repo.id], result[:repo_ids]
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "filters our inaccessible repos from repository_owners" do
          owner1 = create(:user)
          accessible_repo1 = create(:public_repository, :with_codeql_database, owner: owner1)
          inaccessible_repo1 = create(:private_repository, :with_codeql_database, owner: owner1)

          owner2 = create(:user)
          accessible_repo2 = create(:public_repository, :with_codeql_database, owner: owner2)
          inaccessible_repo2 = create(:private_repository, :with_codeql_database, owner: owner2)

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: nil,
            repository_lists: nil,
            repository_owners: [owner1.name, owner2.name]
          )

          assert_same_elements [accessible_repo1.id, accessible_repo2.id], result[:repo_ids]
          assert_empty result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end

        test "doens't leak correct casing of inaccessible repos from repository_nwos" do
          @inaccessible_repo = create(:private_repository, name: "PiCkLeS", owner: create(:user))
          requested_inaccessible_nwo = @inaccessible_repo.nwo.downcase

          result = @helper.resolve_repositories(
            current_user: @helper.current_user,
            cap_filter: @helper.cap_filter,
            language: @language,
            repository_nwos: [@public_repo1.nwo, requested_inaccessible_nwo],
            repository_lists: nil,
            repository_owners: nil
          )

          assert_equal [@public_repo1.id], result[:repo_ids]
          assert_equal [requested_inaccessible_nwo], result[:invalid_repo_nwos]
          assert_empty result[:invalid_repo_lists]
          assert_empty result[:invalid_owners]
        end
      end
    end

    context "resolve repo nwos from ids" do
      test "returns empty array if no ids" do
        result = @helper.resolve_repo_nwos_from_ids([])

        assert_empty result
      end

      test "returns nwos for repo ids" do
        result = @helper.resolve_repo_nwos_from_ids([@public_repo1.id, @public_repo2.id])
        expected_result = {
          @public_repo1.id => @public_repo1.nwo,
          @public_repo2.id => @public_repo2.nwo
        }

        assert_equal expected_result, result
      end

      test "return nwos for repo ids with multiple owners" do
        owner1 = create(:user)
        repo1 = create(:repository, owner: owner1)
        repo2 = create(:repository, owner: owner1)

        owner2 = create(:user)
        repo3 = create(:repository, owner: owner2)
        repo4 = create(:repository, owner: owner2)

        result = @helper.resolve_repo_nwos_from_ids([repo1.id, repo2.id, repo3.id, repo4.id])
        expected_result = {
          repo1.id => repo1.nwo,
          repo2.id => repo2.nwo,
          repo3.id => repo3.nwo,
          repo4.id => repo4.nwo
        }

        assert_equal expected_result, result
      end
    end
  end
end
