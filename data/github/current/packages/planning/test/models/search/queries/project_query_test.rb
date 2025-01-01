# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesProjectQueryTest < GitHub::TestCase
  fixtures do
    setup_search
    @user = create(:user, login: "usethis", plan: "medium", email: "user@fake.org")
    @org = create(:organization)
    @org2 = create(:organization)
    @org.add_member(@user)
    @org2.add_member(@user)

    @repo = create(:repository, owner: @org)
    @private_org_repo = create(:private_repository, owner: @org)
    @repo2 = create(:repository, owner: @org)

    @repo_project = create(:project, owner: @repo, name: "Project 1", closed_at: Time.now)
    @repo_project_with_body = create(:project, owner: @repo, name: "Project 2", body: "For the win")
    @org_project = create(:project, owner: @org, name: "Project 1", closed_at: Time.now)
    @org_project_with_body = create(:project, owner: @org, name: "Project 2", body: "Another win")
    @private_repo_project = create(:project, owner: @private_org_repo, name: "Project 1", closed_at: Time.now)
    make_searchable(@repo_project, @repo_project_with_body, @org_project, @org_project_with_body, @private_repo_project, type: "project")

    @repo2_project = create(:project, owner: @repo2, name: "Project 1")
    @repo2_project_with_body = create(:project, owner: @repo2, name: "Project 2", body: "For the win")
    @org2_project = create(:project, owner: @org2, name: "Project 1")
    @org2_project_with_body = create(:project, owner: @org2, name: "Project 2", body: "Another win")
    make_searchable(@repo2_project, @repo2_project_with_body, @org2_project, @org2_project_with_body, type: "project")
  end

  setup do
    reset_cache
    @repo_query = Search::Queries::ProjectQuery.new(current_user: @user, repo_id: @repo.id, project_type: "repo", aggregations: :state)
    @org_query = Search::Queries::ProjectQuery.new(current_user: @user, org_id: @org.id, project_type: "org", aggregations: :state)
  end

  teardown_once do
    teardown_search
  end

  context "Search scoped to repository" do
    test "private repos require a user" do
      private_repo = create(:private_repository, owner: @user)
      create(:project, owner: private_repo, name: "hiya")
      repo_query = Search::Queries::ProjectQuery.new(current_user: nil, repo_id: private_repo.id, project_type: "repo")
      assert_empty repo_query.execute.results
    end

    test "it will only query projects" do
      assert_equal("project", @repo_query.query_params[:type])
    end

    test "searches by full name" do
      @repo_query.phrase = @repo_project.name
      assert_equal [@repo_project.id.to_s], @repo_query.execute.results.map { |result| result["_id"] }
    end

    test "searches by partial name" do
      query = Search::Queries::ProjectQuery.new(
        current_user: @user,
        repo_id: @repo.id,
        project_type: "repo",
        aggregations: :state
      )
      query.phrase = "Project"
      assert_same_elements [@repo_project.id.to_s, @repo_project_with_body.id.to_s], @repo_query.execute.results.map { |result| result["_id"] }
    end

    test "searches only name" do
      @repo_query.phrase = "For in:name"
      assert_empty @repo_query.execute.results.map { |result| result["_id"] }
    end

    test "searches only closed projects" do
      @repo_query.phrase = "Project is:closed"
      assert_same_elements [@repo_project.id.to_s], @repo_query.execute.results.map { |result| result["_id"] }
    end

    test "searches only open projects" do
      query = Search::Queries::ProjectQuery.new(
        current_user: @user,
        repo_id: @repo.id,
        project_type: "repo",
        aggregations: :state
      )
      query.phrase = "Project is:open"
      assert_same_elements [@repo_project_with_body.id.to_s], query.execute.results.map { |result| result["_id"] }
    end

    test "aggregates open and closed counts for query" do
      @repo_query.phrase = "Project is:open"
      results = @repo_query.execute

      assert_equal 1, results.state_counts["open"]
      assert_equal 1, results.state_counts["closed"]
    end
  end

  context "Search scoped to organization" do
    test "it will only query projects" do
      assert_equal("project", @org_query.query_params[:type])
    end

    test "searches by full name" do
      @org_query.phrase = "#{@org_project.name}"
      assert_equal [@org_project.id.to_s], @org_query.execute.results.map { |result| result["_id"] }
    end

    test "searches by partial name" do
      @org_query.phrase = "Project"
      assert_same_elements [@org_project.id.to_s, @org_project_with_body.id.to_s], @org_query.execute.results.map { |result| result["_id"] }
    end

    test "searches only name" do
      @org_query.phrase = "For in:name"
      assert_empty @org_query.execute.results.map { |result| result["_id"] }
    end

    test "aggregates open and closed counts for query" do
      @org_query.phrase = "Project is:open"
      results = @org_query.execute

      assert_equal 1, results.state_counts["open"]
      assert_equal 1, results.state_counts["closed"]
    end

    context "scoped" do
      test "it fetches org/user projects and repo projects within the owner scope" do
        org_query = Search::Queries::ProjectQuery.new(current_user: @user, org_id: @org.id, project_type: "org", scoped: true)
        results = org_query.execute

        expected = [
          @repo_project,
          @repo_project_with_body,
          @org_project,
          @org_project_with_body,
          @repo2_project,
          @repo2_project_with_body,
          @private_repo_project
        ]

        assert_same_elements expected, results.results.map { |r| r["_model"] }
      end
    end
  end

  context "Search scoped to neither repository nor organization" do
    test "it will reject the query" do
      assert_raises(ArgumentError) { Search::Queries::ProjectQuery.new(current_user: @user).query_document }
    end
  end

  context "Handle security violations gracefully" do
    test "query succeeds with no security violations" do
      query = Search::Queries::ProjectQuery.new(
        current_user: @user,
        org_id: @org.id,
        project_type: "org",
        aggregations: :state
      )
      query.phrase = "Project is:open"
      query.stubs(:security_validation).returns(true)
      results = query.execute
      assert_equal 1, results.count
    end

    test "query succeeds with security violations" do
      query = Search::Queries::ProjectQuery.new(
        current_user: @user,
        org_id: @org.id,
        project_type: "org",
        aggregations: :state
      )
      query.phrase = "Project is:open"
      query.stubs(:security_validation).returns(false)
      results = query.execute
      assert_equal 0, results.count
    end
  end
end
