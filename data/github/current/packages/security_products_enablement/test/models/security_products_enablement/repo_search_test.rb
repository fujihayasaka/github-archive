# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class RepoSearchTest < GitHub::TestCase
    include ConditionalAccess::FilterTestHelper
    include SecurityProductsEnablement::EnterpriseTestHelpers

    fixtures do
      @user = create(:user)
      @user_session = create(:user_session, user: @user)
      @org = create(:organization, admin: @user)

      updated_at = DateTime.now
      create_list(:repository, 5, owner: @org) do |r, _|
        updated_at -= 1.month
        r.update(pushed_at: updated_at)
      end
      create_list(:private_repository, 5, owner: @org) do |r, _|
        updated_at -= 1.month
        r.update(pushed_at: updated_at)
      end
    end

    setup do
      setup_search
      make_searchable(*@org.repositories.to_a)
    end

    teardown do
      teardown_search
    end

    context ".fetch_repos" do
      test "returns repos matching the search query" do
        config = create(:security_configuration, target: @org)
        expected_repos = ::Repository.private_not_internal_scope.where(owner_id: @org.id).order(pushed_at: :desc, id: :asc).limit(5).to_a
        expected_repos.each do |repo|
          create(:repository_security_configuration, repository_id: repo.id, organization_id: @org.id, state: "attached", security_configuration: config)
        end

        result, search_results_limit_exceeded = SecurityProductsEnablement::RepoSearch.fetch_repos(
          query: "configuration:\"#{config.name}\" config-status:attached visibility:private",
          organization: @org,
          actor: @user,
          user_session: @user_session,
          cap_filter: cap_authorizing_filter,
          current_page: 1,
          per_page: 5,
        )

        assert_equal expected_repos.map(&:id), result[:repos].map(&:id)
        refute search_results_limit_exceeded
      end

      test "returns repos matching the search query when the repo_ids_limit_exceeded is true" do
        config = create(:security_configuration, target: @org)
        expected_repos = ::Repository.private_not_internal_scope.where(owner_id: @org.id).order(pushed_at: :desc, id: :asc).limit(5).to_a
        expected_repos.each do |repo|
          create(:repository_security_configuration, repository_id: repo.id, organization_id: @org.id, state: "attached", security_configuration: config)
        end

        act_as(@user)
        result, search_results_limit_exceeded =
          stub_const(SecurityProductsEnablement::ListReposQuery, :RESULTS_LIMIT, 1) do
            SecurityProductsEnablement::RepoSearch.fetch_repos(
              query: "configuration:\"#{config.name}\" config-status:attached visibility:private",
              organization: @org,
              actor: @user,
              user_session: @user_session,
              cap_filter: cap_authorizing_filter,
              current_page: 1,
              per_page: 5,
            )
          end

        assert_equal expected_repos.map(&:id), result[:repos].map(&:id)
      end
    end

    context ".find_repo_ids_with_offset_pagination" do
      test "returns repo IDs that match the given search filters" do
        config = create(:security_configuration, target: @org)
        expected_repo_ids = ::Repository.where(owner_id: @org.id).order(pushed_at: :desc, id: :asc).pluck(:id)
        expected_repo_ids.each do |id|
          create(:repository_security_configuration, repository_id: id, organization_id: @org.id, state: "attached", security_configuration: config)
        end

        act_as(@user)
        results = SecurityProductsEnablement::RepoSearch.find_repo_ids_with_offset_pagination(
          query: "configuration:\"#{config.name}\" config-status:attached visibility:private,public,internal",
          organization: @org,
          actor: @user,
          user_session: @user_session,
          cap_filter: cap_authorizing_filter,
          per_page: 5,
        )

        assert_equal expected_repo_ids, results
      end

      test "returns repos matching the search query when the repo_ids_limit_exceeded is true" do
        config = create(:security_configuration, target: @org)
        expected_repo_ids = ::Repository.where(owner_id: @org.id).order(pushed_at: :desc, id: :asc).pluck(:id)
        expected_repo_ids.each do |id|
          create(:repository_security_configuration, repository_id: id, organization_id: @org.id, state: "attached", security_configuration: config)
        end

        act_as(@user)
        results =
          stub_const(SecurityProductsEnablement::ListReposQuery, :RESULTS_LIMIT, 1) do
            SecurityProductsEnablement::RepoSearch.find_repo_ids_with_offset_pagination(
              query: "configuration:\"#{config.name}\" config-status:attached visibility:private,public,internal",
              organization: @org,
              actor: @user,
              user_session: @user_session,
              cap_filter: cap_authorizing_filter,
              per_page: 5,
            )
          end

        assert_equal expected_repo_ids, results
      end
    end

    context ".find_repo_ids_with_cursor_pagination" do
      test "returns repo IDs that match the given search filters" do
        config = create(:security_configuration, target: @org)
        expected_repo_ids = ::Repository.where(owner_id: @org.id).order(pushed_at: :desc, id: :asc).pluck(:id)
        expected_repo_ids.each do |id|
          create(:repository_security_configuration, repository_id: id, organization_id: @org.id, state: "attached", security_configuration: config)
        end

        act_as(@user)
        results = SecurityProductsEnablement::RepoSearch.find_repo_ids_with_cursor_pagination(
          query: "configuration:\"#{config.name}\" config-status:attached visibility:private,public,internal",
          organization: @org,
          actor: @user,
          user_session: @user_session,
          cap_filter: cap_authorizing_filter,
          per_page: 5,
        )

        assert_equal expected_repo_ids, results
      end
    end
  end
end
