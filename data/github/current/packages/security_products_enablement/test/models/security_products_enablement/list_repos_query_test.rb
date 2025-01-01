# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class ListReposQueryTest < GitHub::TestCase
    include SecurityProductsEnablement::EnterpriseTestHelpers

    fixtures do
      business = create(:global_business)
      @user = create(:user)
      @org = create(:organization, business: business, admin: @user)
      @team = create(:team, organization: @org, name: "test-team")

      @repo1 = create(:repository, owner: @org)
      @repo2 = create(:private_repository, owner: @org)
      @repo3 = create(:internal_repository, owner: @org)
      @repo4 = create(:repository, owner: @org)

      @repo1.add_team(@team, action: :write)
      @repo3.add_team(@team, action: :write)

      create_repo_security_center_config(repository: @repo1, ghas_enabled: false)
      create_repo_security_center_config(repository: @repo2, ghas_enabled: true, features: { secret_scanning: "not_enrolled" })
      create_repo_security_center_config(repository: @repo3, ghas_enabled: true, features: { secret_scanning: "not_enrolled" })
      create_repo_security_center_config(repository: @repo4, ghas_enabled: false)
    end

    setup do
      @config1 = create(:security_configuration, target: @org)
      @config2 = create(:security_configuration, target: @org)

      create(:repository_security_configuration, repository: @repo1, security_configuration: @config1, state: :attached)
      create(:repository_security_configuration, repository: @repo2, security_configuration: @config2, state: :removed)
      create(:repository_security_configuration, repository: @repo3, security_configuration: @config2, state: :failed)
      create(:repository_security_configuration, repository: @repo4, security_configuration: @config2, state: :enforced)
    end

    def create_repo_security_center_config(repository:, ghas_enabled: true, features: {})
      create(:repository_security_center_config, repository:, ghas_enabled:)

      features.each do |feature, scanning_status|
        create(:repository_security_center_status, feature, scanning_status:, scanning_count: 0, repository:)
      end
    end

    context "#repository_ids" do
      test "returns repo IDs that match the given search filters" do
        query = SecurityProductsEnablement::ListReposQuery.new(
          org: @org,
          user: @user,
          filter_hash: {
            "team" => [@team.name],
            "configuration" => [@config1.name, @config2.name],
            "config-status" => %w(attached failed)
          }
        )

        repo_ids, search_results_limit_exceeded = query.repository_ids

        assert_equal [@repo3.id, @repo1.id], repo_ids
        refute search_results_limit_exceeded, "Expected search_results_limit_exceeded to be false"

        @repo4.add_team(@team, action: :write)
        repo_ids, _ = query.repository_ids
        assert_equal [@repo4.id, @repo3.id, @repo1.id], repo_ids
      end

      test "returns an empty array when nothing matches the search filters" do
        query = SecurityProductsEnablement::ListReposQuery.new(
          org: @org,
          user: @user,
          filter_hash: {
            "configuration" => ["random name"],
            "config-status" => %w(attached failed)
          }
        )
        repo_ids, _ = query.repository_ids
        assert_equal [], repo_ids

        search_query = "advanced-security:disabled config-status:removed"
        query = SecurityProductsEnablement::ListReposQuery.new(
          org: @org,
          user: @user,
          filter_hash: Search::Queries::SecurityConfigurations::RepositoryQuery.new(query: search_query).mysql_query_hash
        )
        repo_ids, _ = query.repository_ids
        assert_equal [], repo_ids
      end

      test "returns an empty array when the given filters are not supported" do
        query = SecurityProductsEnablement::ListReposQuery.new(
          org: @org,
          user: @user,
          filter_hash: {
            "not-supported" => ["random name"],
            "random-filter" => ["hello world"]
          }
        )

        repo_ids, _ = query.repository_ids
        assert_equal [], repo_ids
      end

      test "does not truncate results when apply_results_limit is false" do
        stub_const(SecurityProductsEnablement::ListReposQuery, :RESULTS_LIMIT, 1) do
          query = SecurityProductsEnablement::ListReposQuery.new(
            org: @org,
            user: @user,
            filter_hash: {
              "team" => [@team.name],
              "configuration" => [@config1.name, @config2.name],
              "config-status" => %w(attached failed)
            }
          )

          repo_ids, search_results_limit_exceeded = query.repository_ids
          assert_equal [@repo3.id, @repo1.id], repo_ids
          assert search_results_limit_exceeded
        end
      end

      test "supports advanced filters" do
        search_query = "advanced-security:enabled secret-scanning-alerts:disabled"
        query = SecurityProductsEnablement::ListReposQuery.new(
          org: @org,
          user: @user,
          filter_hash: Search::Queries::SecurityConfigurations::RepositoryQuery.new(query: search_query).mysql_query_hash
        )

        repo_ids, _ = query.repository_ids
        assert_equal [@repo3.id, @repo2.id], repo_ids
      end

      test "supports advanced filters in combination with other filters" do
        search_query = "-advanced-security:enabled config-status:attached"
        query = SecurityProductsEnablement::ListReposQuery.new(
          org: @org,
          user: @user,
          filter_hash: Search::Queries::SecurityConfigurations::RepositoryQuery.new(query: search_query).mysql_query_hash
        )

        repo_ids, _ = query.repository_ids
        assert_equal [@repo4.id, @repo1.id], repo_ids
      end
    end
  end
end
