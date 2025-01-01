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
    end

    setup do
      @config1 = create(:security_configuration, target: @org)
      @config2 = create(:security_configuration, target: @org)

      create(:repository_security_configuration, repository: @repo1, security_configuration: @config1, state: :attached)
      create(:repository_security_configuration, repository: @repo2, security_configuration: @config2, state: :removed)
      create(:repository_security_configuration, repository: @repo3, security_configuration: @config2, state: :failed)
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

      test "truncate results when the total number exceeds the limit" do
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
          assert_equal [@repo3.id], repo_ids
          assert search_results_limit_exceeded, "Expected search_results_limit_exceeded to be true"
        end
      end
    end
  end
end
