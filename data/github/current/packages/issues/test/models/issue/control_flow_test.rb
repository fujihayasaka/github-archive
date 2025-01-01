# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueControlFlowTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @repo  = create(:repository, has_issues: false)
    @owner = @repo.owner
    @flow  = Issue::ControlFlow.new(params: { q: "is:open".dup }, repo: @repo)
  end

  test "accepts options" do
    params = { q: "is:open".dup }
    flow   = Issue::ControlFlow.new(params: params, repo: @repo)

    assert_equal params,     flow.params
    assert_equal params[:q], flow.query
  end

  test "only accepts string queries" do
    params = { q: { "foo" => "bar" } }
    flow   = Issue::ControlFlow.new(params: params, repo: @repo)

    assert_equal params,     flow.params
    assert_equal "is:pr is:open", flow.query
  end

  test "the query for pulls only" do
    params = { q: "is:open is:issue".dup, pulls_only: true }
    flow   = Issue::ControlFlow.new(params: params, repo: @repo)

    assert_equal "is:open is:pr", flow.query
  end

  test "has issues" do
    assert !@flow.has_issues
  end

  test "needs_disabled_redirect?" do
    assert @flow.needs_disabled_redirect?
  end

  test "rewritten_path_for_disabled_issues" do
    flow = Issue::ControlFlow.new(params: { q: "is:open".dup }, repo: @repo)
    assert_equal "/#{@repo.nwo}/pulls?q=is%3Aopen", flow.rewritten_path_for_disabled_issues
  end

  test "rewritten_path_for_disabled_issues for blank query" do
    flow = Issue::ControlFlow.new(params: { q: "".dup }, repo: @repo)
    assert_equal "/#{@repo.nwo}/pulls", flow.rewritten_path_for_disabled_issues
  end

  test "force_pulls" do
    disable_feature_flag(:issues_advanced_search)
    flow = Issue::ControlFlow.new(params: { assignee: "holman" }, repo: @repo)
    assert flow.force_pulls?
  end

  test "force_pulls on pulls_only" do
    disable_feature_flag(:issues_advanced_search)
    flow = Issue::ControlFlow.new(params: { pulls_only: true }, repo: @repo)
    assert flow.force_pulls?
  end

  test "old issues-next milestone number URLs" do
    milestone = create(:milestone, repository: create(:repository))
    flow = Issue::ControlFlow.new(params: { milestone: milestone.number }, repo: milestone.repository)
    assert_equal "is:issue is:open milestone:\"#{milestone.title}\"", flow.query
  end

  test "non-numeric milestone ids are ignored" do
    flow = Issue::ControlFlow.new(params: { milestone: "none" },
                                  repo: @repo)
    assert_equal "is:pr is:open", flow.query
  end

  test "only cleans on no-pagination links" do
    query = "is:open is:issue assignee:holman".dup
    components = Search::Queries::IssueQuery.parse(query)
    flow = Issue::ControlFlow.new(params: { q: query, page: 2 }, components: components, repo: @has_issues)
    refute flow.has_query_state_params?
  end

  test "normalizes page numbers" do
    params = { page: { "foo" => "bar" } }
    flow   = Issue::ControlFlow.new(params: params, repo: @repo)

    assert_equal params,     flow.params
    assert_equal 1, flow.params[:page]
  end

  test "does not add user component if exists" do
    query = "is:open is:issue"
    components = Search::Queries::IssueQuery.parse(query)
    flow = Issue::ControlFlow.new(params: { q: query, user: "github" }, components: components)

    assert flow.query == "is:open is:issue user:github"

    query = "is:open is:issue user:github"
    components = Search::Queries::IssueQuery.parse(query)
    flow = Issue::ControlFlow.new(params: { q: query, user: "github", page: 2 },
      components: components)

    assert flow.query == "is:open is:issue user:github"
  end

  test "does not add archived:false to /issues with no query parameters" do
    params = ActionController::Parameters.new({})
    flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
    assert_equal "is:open is:issue", flow.query
  end

  test "does not add archived:false to /issues with query parameters" do
    query = "is:open is:issue author:#{@owner.display_login}"
    params = ActionController::Parameters.new({ q: query })
    flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
    assert_equal query, flow.query
  end

  test "adds archived:false to /issues with no query parameters and exclude_archived" do
    params = ActionController::Parameters.new({})
    flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner, exclude_archived: true)
    assert_equal "is:open is:issue archived:false", flow.query
  end

  test "does not add archived:false to /issues with query parameters and exclude_archived" do
    query = "is:open is:issue author:#{@owner.display_login}"
    params = ActionController::Parameters.new({ q: query })
    flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner, exclude_archived: true)
    assert_equal query, flow.query
  end

  context "dashboard URLs" do
    test "redirects to /issues" do
      params = ActionController::Parameters.new({ q: "is:open is:issue author:#{@owner.display_login}".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/issues", flow.redirect_path
    end

    test "does not redirect to /issues with archived:false" do
      params = ActionController::Parameters.new({ q: "is:open is:issue author:#{@owner.display_login} archived:false".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      refute_equal "/issues", flow.redirect_path
    end

    test "does not redirect to /issues with archived:true" do
      params = ActionController::Parameters.new({ q: "is:open is:issue author:#{@owner.display_login} archived:true".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      refute_equal "/issues", flow.redirect_path
    end

    test "does not redirect to /issues with exclude_archived and archived unset" do
      params = ActionController::Parameters.new({ q: "is:open is:issue author:#{@owner.display_login}".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner, exclude_archived: true)
      refute_equal "/issues", flow.redirect_path
    end

    test "redirects to /issues with exclude_archived and archived:false" do
      params = ActionController::Parameters.new({ q: "is:open is:issue author:#{@owner.display_login} archived:false".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner, exclude_archived: true)
      assert_equal "/issues", flow.redirect_path
    end

    test "does not redirect to /issues with with exclude_archived and archived:true" do
      params = ActionController::Parameters.new({ q: "is:open is:issue author:#{@owner.display_login} archived:true".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner, exclude_archived: true)
      refute_equal "/issues", flow.redirect_path
    end

    test "redirects to /issues/assigned" do
      params = ActionController::Parameters.new({ q: "is:open is:issue assignee:#{@owner.display_login}".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/issues/assigned", flow.redirect_path
    end

    test "redirects to /issues/mentioned" do
      params = ActionController::Parameters.new({ q: "is:open is:issue mentions:#{@owner.display_login}".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/issues/mentioned", flow.redirect_path
    end

    test "redirects to /pulls" do
      params = ActionController::Parameters.new({ q: "is:open is:pr author:#{@owner.display_login}".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/pulls", flow.redirect_path
    end

    test "redirects to /pulls/assigned" do
      params = ActionController::Parameters.new({ q: "is:open is:pr assignee:#{@owner.display_login}".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/pulls/assigned", flow.redirect_path
    end

    test "redirects to /pulls/mentioned" do
      params = ActionController::Parameters.new({ q: "is:open is:pr mentions:#{@owner.display_login}".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/pulls/mentioned", flow.redirect_path
    end

    test "author:non-current_user isn't a clean url" do
      params = ActionController::Parameters.new({ q: "is:open is:issue author:defunkt".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_nil flow.redirect_path
    end

    test "is:queued isn't a clean url" do
      params = ActionController::Parameters.new({ q: "is:open is:pr is:queued".dup })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      refute_predicate flow, :clean_url?
      assert_nil flow.redirect_path
    end

    test "(author|assignee|mentions|review-requested):@me isn't a clean url" do
      queries = [
        "is:open is:issue author:@me",
        "is:open is:issue assignee:@me",
        "is:open is:issue mentions:@me",
        "is:open is:pr review-requested:@me",
      ]

      queries.each do |query|
        params = ActionController::Parameters.new({ q: query })
        flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
        refute_predicate flow, :clean_url?
        assert_nil flow.redirect_path
      end
    end

    test "ignores state parameter" do
      params = ActionController::Parameters.new({ q: "is:open is:pr author:#{@owner.display_login}".dup, state: "" })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/pulls", flow.redirect_path
    end

    test "ignores labels parameter" do
      params = ActionController::Parameters.new({ q: "is:open is:pr author:#{@owner.display_login}".dup, labels: "" })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/pulls", flow.redirect_path
    end

    test "ignores sort parameter" do
      params = ActionController::Parameters.new({ q: "is:open is:pr author:#{@owner.display_login}".dup, sort: "" })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/pulls", flow.redirect_path
    end

    test "ignores direction parameter" do
      params = ActionController::Parameters.new({ q: "is:open is:pr author:#{@owner.display_login}".dup, direction: "" })
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)
      assert_equal "/pulls", flow.redirect_path
    end
  end

  context "rewritten_path_for_clean_url" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @has_issues = create(:repository, has_issues: true)
      @only_pulls = create(:repository, has_issues: false)
    end

    test "queries always redirect" do
      flow = setup_flow("is:open is:issue label:bug crash", @has_issues)
      assert_nil flow.rewritten_path_for_clean_url
    end

    test "is:public urls aren't clean" do
      flow = setup_flow("is:open is:issue author:holman is:public", @has_issues)
      assert_nil flow.rewritten_path_for_clean_url
    end

    test "is:private urls aren't clean" do
      flow = setup_flow("is:open is:issue author:holman is:private", @has_issues)
      assert_nil flow.rewritten_path_for_clean_url
    end

    test "issues assignee" do
      flow = setup_flow("is:open is:issue assignee:holman", @has_issues)
      assert_equal "/#{@has_issues.nwo}/issues/assigned/holman", flow.rewritten_path_for_clean_url
    end

    test "issues assignee without explict type" do
      flow = setup_flow("is:open assignee:holman", @has_issues)
      assert_nil flow.rewritten_path_for_clean_url
    end

    test "open and closed issues for someone" do
      flow = setup_flow("is:issue author:holman", @has_issues)
      refute flow.rewritten_path_for_clean_url
    end

    test "open and closed pulls for someone" do
      flow = setup_flow("is:pr author:holman", @has_issues)
      refute flow.rewritten_path_for_clean_url
    end

    test "incomplete author" do
      flow = setup_flow("is:pr author:", @has_issues)
      refute flow.rewritten_path_for_clean_url
    end

    test "author with a trailing slash" do
      flow = setup_flow("is:issue is:open author:user/", @has_issues)
      assert_equal "/#{@has_issues.nwo}/issues/created_by/user", flow.rewritten_path_for_clean_url
    end

    test "author with a leading slash" do
      flow = setup_flow("is:issue is:open author:/user", @has_issues)
      assert_equal "/#{@has_issues.nwo}/issues/created_by/user", flow.rewritten_path_for_clean_url
    end

    test "closed pulls for someone" do
      flow = setup_flow("is:closed type:pr author:holman", @has_issues)
      flow.current_path = "/#{@has_issues.nwo}/issues?q=#{flow.query}"
      assert_equal "/#{@has_issues.nwo}/pulls?q=is%3Aclosed+type%3Apr+author%3Aholman", flow.rewritten_path_for_clean_url
    end

    test "case insensitive name with owner" do
      flow = setup_flow("is:open type:pr", @has_issues)
      flow.current_path = "/#{@has_issues.nwo.upcase}/issues?q=#{flow.query}"
      assert_equal "/#{@has_issues.nwo}/pulls?q=is%3Aopen+type%3Apr", flow.rewritten_path_for_clean_url
    end

    test "pulls assignee" do
      flow = setup_flow("is:open type:pr assignee:holman", @has_issues)
      assert_equal "/#{@has_issues.nwo}/pulls/assigned/holman", flow.rewritten_path_for_clean_url
    end

    test "pulls assignee for issues disabled" do
      flow = setup_flow("is:open is:issue assignee:holman", @only_pulls)
      assert_equal "/#{@only_pulls.nwo}/pulls/assigned/holman", flow.rewritten_path_for_clean_url
    end

    test "pulls assignee for explicit pulls" do
      flow = setup_flow("is:open type:pr assignee:holman", @has_issues)
      flow.pulls_only = true
      assert_equal "/#{@has_issues.nwo}/pulls/assigned/holman", flow.rewritten_path_for_clean_url
    end

    test "correctly sets pulls_only from query with multiple is criteria" do
      flow = setup_flow("is:open is:issue assignee:iolsen", @has_issues)
      refute flow.pulls_only
      flow = setup_flow("is:issue is:open assignee:iolsen", @has_issues)
      refute flow.pulls_only

      flow = setup_flow("is:open is:pr assignee:iolsen", @has_issues)
      assert flow.pulls_only
      flow = setup_flow("is:pr is:open assignee:iolsen", @has_issues)
      assert flow.pulls_only
    end

    test "issues author" do
      flow = setup_flow("is:open is:issue author:holman", @has_issues)
      assert_equal "/#{@has_issues.nwo}/issues/created_by/holman", flow.rewritten_path_for_clean_url
    end

    test "any issues URL with is:pr should be redirected to a pulls URL" do
      flow = setup_flow("is:open is:pr comments:>50", @has_issues)
      flow.current_path = "/#{@has_issues.nwo}/issues?q=#{flow.query}"
      assert_equal "/#{@has_issues.nwo}/pulls?q=#{CGI::escape(flow.query)}", flow.rewritten_path_for_clean_url
    end

    test "pulls author" do
      flow = setup_flow("is:open is:issue author:holman", @only_pulls)
      assert_equal "/#{@only_pulls.nwo}/pulls/holman", flow.rewritten_path_for_clean_url
    end

    test "issues mentions" do
      flow = setup_flow("is:open is:issue mentions:holman", @has_issues)
      assert_equal "/#{@has_issues.nwo}/issues/mentioned/holman", flow.rewritten_path_for_clean_url
    end

    test "pulls mentions" do
      flow = setup_flow("is:open is:issue mentions:holman", @only_pulls)
      assert_equal "/#{@only_pulls.nwo}/pulls/mentioned/holman", flow.rewritten_path_for_clean_url
    end

    test "labels" do
      flow = setup_flow("is:open label:bug", @has_issues)
      assert_equal "/#{@has_issues.nwo}/labels/bug", flow.rewritten_path_for_clean_url
    end

    test "labels isn't greedy" do
      flow = setup_flow("is:open label:bug sort:updated-asc", @has_issues)
      assert_nil flow.rewritten_path_for_clean_url
    end

    test "multiple labels aren't greedy, either" do
      flow = setup_flow("is:open label:bug label:issues", @has_issues)
      assert_nil flow.rewritten_path_for_clean_url
    end

    test "enumerated labels aren't greedy" do
      flow = setup_flow("is:open label:bug,issues", @has_issues)
      assert_nil flow.rewritten_path_for_clean_url
    end

    test "excluding labels doesn't cause an error" do
      flow = setup_flow("is:open -label:bug", @has_issues)
      assert_nil flow.rewritten_path_for_clean_url
    end

    test "milestones" do
      flow = setup_flow("is:open milestone:shipit", @only_pulls)
      assert_equal "/#{@only_pulls.nwo}/milestones/shipit", flow.rewritten_path_for_clean_url
    end

    test "milestones can be without state" do
      flow = setup_flow("milestone:shipit", @only_pulls)
      assert_nil flow.rewritten_path_for_clean_url
    end

    test "with search" do
      flow = setup_flow("is:open is:issue author:shipit test", @has_issues)
      assert_nil flow.rewritten_path_for_clean_url
    end
  end

  context "#applied_dashboard_tab_filter_name" do
    test "returns created when given created_by params" do
      params = { created_by: true }
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)

      assert_equal "Created", flow.applied_dashboard_tab_filter_name
    end

    test "returns assigned when given assigned params" do
      params = { assigned: true }
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)

      assert_equal "Assigned", flow.applied_dashboard_tab_filter_name
    end

    test "returns mentioned when given mentioned params" do
      params = { mentioned: true }
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)

      assert_equal "Mentioned", flow.applied_dashboard_tab_filter_name
    end

    test "returns review requests when given review requested params" do
      params = { review_requested: true }
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)

      assert_equal "Review requests", flow.applied_dashboard_tab_filter_name
    end

    test "returns nil when not given preset filter params" do
      params = {}
      flow = Issue::ControlFlow.new(params: params, repo: nil, current_user: @owner)

      assert_nil flow.applied_dashboard_tab_filter_name
    end
  end

  def setup_flow(query, repo)
    query = query.dup if query.frozen?
    components = Search::Queries::IssueQuery.parse(query)
    flow = Issue::ControlFlow.new(params: { q: query }, components: components, repo: repo)
  end
end
