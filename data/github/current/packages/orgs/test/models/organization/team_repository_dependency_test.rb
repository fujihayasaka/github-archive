# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::TeamRepositoryDependencyTest < GitHub::TestCase

  fixtures do
    @org = create :organization
    @admin = @org.admins.first
    @pub_org_repo = create :public_repository, owner: @org, name: "pub_org_repo"
    @priv_org_repo = create :private_repository, owner: @org, name: "priv_org_repo"

    @other_org = create :organization, admin: @admin
    @other_pub_repo = create :public_repository, owner: @other_org, name: "other_pub_repo"
    @other_priv_repo = create :private_repository, owner: @other_org, name: "other_priv_repo"
  end

  def to_results(*repos)
    Array.wrap(repos).map { |repo| [repo.public?, repo.id] }
  end

  context "repositories_for_team_repo_connection" do
    test "combines queries and then seperates results by org" do
      p1 = @org.async_batch_repositories_for_team_repo_connection(@admin)
      p2 = @org.async_batch_repositories_for_team_repo_connection(@admin)
      p3 = @other_org.async_batch_repositories_for_team_repo_connection(@admin)

      results, queries = log_cleaned_queries do
        Promise.all([p1, p2, p3]).sync
      end

      r1, r2, r3 = results
      assert_same_elements to_results(@pub_org_repo, @priv_org_repo), r1
      assert_same_elements r1, r2
      assert_same_elements to_results(@other_pub_repo, @other_priv_repo), r3
      assert_equal 1, queries.size
    end

    test "orders results" do
      asc_promise = @org.async_batch_repositories_for_team_repo_connection(@admin, nil, { id: "asc" })
      desc_promise = @org.async_batch_repositories_for_team_repo_connection(@admin, nil, { id: "desc" })

      asc, desc = Promise.all([asc_promise, desc_promise]).sync

      expected = to_results(@pub_org_repo, @priv_org_repo).sort_by! { |r| r[1] }
      assert_equal expected, asc
      assert_equal expected.reverse, desc
    end

    test "filters results" do
      pub_promise = @org.async_batch_repositories_for_team_repo_connection(@admin, "pub_")
      both_promise = @org.async_batch_repositories_for_team_repo_connection(@admin, "_org_repo")

      pub, both = Promise.all([pub_promise, both_promise]).sync

      assert_same_elements to_results(@pub_org_repo), pub
      assert_same_elements to_results(@pub_org_repo, @priv_org_repo), both
    end

    test "hides private repos when no viewer" do
      results = @org.async_batch_repositories_for_team_repo_connection.sync
      assert_same_elements to_results(@pub_org_repo), results
    end

    test "includes extra fields" do
      asc_promise = @org.async_batch_repositories_for_team_repo_connection(@admin, "", { name: "asc" }, [:name])
      desc_promise = @org.async_batch_repositories_for_team_repo_connection(@admin, "", { name: "desc" }, [:name])

      asc, desc = Promise.all([asc_promise, desc_promise]).sync

      expected = [
        [false, @priv_org_repo.id, "priv_org_repo"],
        [true, @pub_org_repo.id, "pub_org_repo"]
      ]
      assert_equal expected, asc
      assert_equal expected.reverse, desc
    end
  end
end
