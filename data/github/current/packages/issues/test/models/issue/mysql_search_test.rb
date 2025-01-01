# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueMySqlSearchTest < GitHub::TestCase
  fixtures do
    @bestra = create(:user, login: "bestra", email: "bestra@example.com")
  end

  test "supported queries" do
    assert Issue::MysqlSearch.supported?("is:open")
    assert Issue::MysqlSearch.supported?("is:closed")
    assert Issue::MysqlSearch.supported?("is:issue")
    assert Issue::MysqlSearch.supported?("is:pr")
    assert Issue::MysqlSearch.supported?("author:holman")
    assert Issue::MysqlSearch.supported?("milestone:\"Issues 3\"")
    assert Issue::MysqlSearch.supported?("assignee:josh")
    assert Issue::MysqlSearch.supported?("-assignee:josh")
    assert Issue::MysqlSearch.supported?("sort:created-asc")
    assert Issue::MysqlSearch.supported?("sort:reactions")
    assert Issue::MysqlSearch.supported?("sort:reactions-smile")
    assert Issue::MysqlSearch.supported?("is:merged")
    assert Issue::MysqlSearch.supported?("is:unmerged")
    assert Issue::MysqlSearch.supported?("no:assignee")
    assert Issue::MysqlSearch.supported?("no:milestone")
    assert Issue::MysqlSearch.supported?("author:draft")
    assert Issue::MysqlSearch.supported?("type:issue")
    assert Issue::MysqlSearch.supported?("type:pr")

    refute Issue::MysqlSearch.supported?("github")
    refute Issue::MysqlSearch.supported?("is:open github")
    refute Issue::MysqlSearch.supported?("is:closed github")
    refute Issue::MysqlSearch.supported?("team:github/issues")
    refute Issue::MysqlSearch.supported?("no:label")
    refute Issue::MysqlSearch.supported?("-label:bitcoin")
    refute Issue::MysqlSearch.supported?("is:open is:issue -label:bitcoin no:milestone")
    refute Issue::MysqlSearch.supported?("is:open is:issue no:milestone -label:bitcoin")
    refute Issue::MysqlSearch.supported?("is:open label:bug label:feature")
    refute Issue::MysqlSearch.supported?("mentions:holman")
    refute Issue::MysqlSearch.supported?("merged:>2014-07-11")
    refute Issue::MysqlSearch.supported?("closed:>2014-07-11")
    refute Issue::MysqlSearch.supported?("created:>2014-07-11")
    refute Issue::MysqlSearch.supported?("updated:>2014-07-11")
    refute Issue::MysqlSearch.supported?("comments:2")
    refute Issue::MysqlSearch.supported?("sort:interactions-asc")
    refute Issue::MysqlSearch.supported?("is:draft")
    refute Issue::MysqlSearch.supported?("is:queued")
    refute Issue::MysqlSearch.supported?("type:Bug")
    refute Issue::MysqlSearch.supported?("type:issue type:Bug")
  end

  test "enumerated labels are not supported" do
    # These queries should be run through ES. With the flag on we interpret `label:one,two`
    # as multiple labels values.
    refute Issue::MysqlSearch.supported?("label:bug,feature", @bestra)
    refute Issue::MysqlSearch.supported?('label:bug,"feature flag"', @bestra)

    # This function assumes the current_user is `nil` when omitted
    refute Issue::MysqlSearch.supported?("label:bug,feature")
    refute Issue::MysqlSearch.supported?('label:bug,"feature flag"')
  end

  test "single labels are not suported" do
    refute Issue::MysqlSearch.supported?("label:bug")
  end

  test "has_any_labels?" do
    query = [[:is, "pr"]]
    refute Issue::MysqlSearch.has_any_labels?(query, nil)

    query = [[:label, "love"], [:is, "pr"]]
    assert Issue::MysqlSearch.has_any_labels?(query, nil)

    query = [[:label, "love"], [:label, "peace"], [:is, "pr"]]
    assert Issue::MysqlSearch.has_any_labels?(query, nil)

    query = [[:label, %w[love peace]], [:is, "pr"]]
    assert Issue::MysqlSearch.has_any_labels?(query, nil)
  end

  test "sort_scope direction safety" do
    Issue::MysqlSearch.sort_scope("updated-desc", Issue.all)
    Issue::MysqlSearch.sort_scope("updated", Issue.all)
    Issue::MysqlSearch.sort_scope("updated-asc", Issue.all)
    Issue::MysqlSearch.sort_scope("updated-", Issue.all)
  end
end

class MySqlEquivalenceWithElasticsearchTest < GitHub::TestCase
  fixtures do
    @owner     = create(:user)
    @repo      = create(:repository, owner: @owner, from_example: :pull_request_fork)
    @spammy_user = create(:spammy_user)
    @spammy_repo = create(:repository, owner: @spammy_user, user_hidden: 1)
    @milestone = create(:milestone, repository: @repo)
    @label     = create(:label, repository: @repo, name: "Something Wicked")
    @label2    = create(:label, repository: @repo)
    @label3    = create(:label, repository: @repo)
    @emoji_label = create(:label, repository: @repo, name: "ready-for-review \u{1f440}")

    issues = T.let([], T::Array[Issue])

    Time.use_zone "Australia/Melbourne" do
      Timecop.freeze(Time.zone.parse("September 09 2014 9:41 AM")) do
        issues << create(:issue, repository: @repo,
                             user: @owner,
                             body: "This is an open issue.",
                             assignee: @owner,
                             milestone_id: @milestone.id)

        last_issue = T.must(issues.last)
        create(:issue_comment, issue: last_issue)
        create(:issue_comment, issue: last_issue)
        create(:issue_comment, issue: last_issue)
        last_issue.add_labels([@label, @label2, @emoji_label])
        last_issue.update_column(:created_at, 6.days.ago)
        last_issue.update_column(:updated_at, 6.days.ago)

        issues << create(:issue, repository: @repo,
                             user: @owner,
                             body: "This is a closed issue.",
                             state: "closed")

        last_issue = T.must(issues.last)
        create(:issue_comment, issue: last_issue)
        create(:issue_comment, issue: last_issue)
        last_issue.update_column(:created_at, 5.days.ago)
        last_issue.update_column(:updated_at, 5.days.ago)
        last_issue.update_column(:closed_at,  5.days.ago)
        Reaction.react(user: @owner, subject_id: last_issue.id, subject_type: last_issue.class.name, content: "smile")
        Reaction.react(user: create(:user), subject_id: last_issue.id, subject_type: last_issue.class.name, content: "smile")

        issues << create(:issue, repository: @repo,
                             user: @owner,
                             pull_request: @repo.comparison("master", "topic").build_pull_request(user: @owner))

        last_issue = T.must(issues.last)
        create(:issue_comment, issue: last_issue)
        last_issue.add_labels([@label, @label2, @label3])
        last_issue.update_column(:created_at, 4.days.ago)
        last_issue.update_column(:updated_at, 4.days.ago)
        T.must(last_issue.pull_request).update_column(:created_at, 4.days.ago)
        T.must(last_issue.pull_request).update_column(:updated_at, 4.days.ago)
        T.must(last_issue.pull_request).update_column(:merged_at,  4.days.ago)

        issues << create(:issue, repository: @repo,
                             body: "hey #{@owner.login} why don't we just add more managers",
                             user: create(:user),
                             assignee: @owner)

        last_issue = T.must(issues.last)
        last_issue.update_column(:created_at, 3.days.ago)
        last_issue.update_column(:updated_at, 3.days.ago)
        Reaction.react(user: @owner, subject_id: last_issue.id, subject_type: last_issue.class.name, content: "smile")

        issues << create(:issue, repository: @spammy_repo, user: @spammy_user, body: "This is an issue of a spammy user.")

        issue_index = Elastomer::Indexes::Issues.new
        pull_index  = Elastomer::Indexes::PullRequests.new

        issues.each do |issue|
          if issue.pull_request?
            adapter = Elastomer::Adapters::PullRequest.create(issue.pull_request)
            pull_index.store(adapter)
          else
            adapter = Elastomer::Adapters::Issue.create(issue)
            issue_index.store(adapter)
          end
        end

        issue_index.refresh
        pull_index.refresh
      end
    end
  end

  teardown do
    GitHub.cache.clear
  end

  test "finds issues with specified label" do
    result = Issue::MysqlSearch.search(repo: @repo, query: %Q(label:"#{@emoji_label.name}"))

    assert_equal 1, result[:open_count]
    assert_includes result[:issues].first.labels, @emoji_label
  end

  test "finds open issues with specified label" do
    result = Issue::MysqlSearch.search(repo: @repo, query: %Q(is:open label:"#{@emoji_label.name}"))

    assert_equal 1, result[:open_count]
    assert_includes result[:issues].first.labels, @emoji_label
  end

  test "issues disabled" do
    @repo.has_issues = false

    issues = Issue::MysqlSearch.search(repo: @repo, query: "is:open")[:issues]
    assert_empty issues.select { |issue| issue.pull_request.nil? }
  end

  # Deprecated in favor of :force_type
  test "force to pulls" do
    issues = Issue::MysqlSearch.search(repo: @repo, query: "is:open", force_pulls: true)[:issues]
    assert_empty issues.select { |issue| issue.pull_request.nil? }
  end

  test "force to pull requests" do
    issues = Issue::MysqlSearch.search(repo: @repo, query: "is:open", force_type: :pull_requests)[:issues]
    assert_empty issues.select { |issue| issue.pull_request.nil? }
  end

  test "force to pull requests overrides force_pulls" do
    issues = Issue::MysqlSearch.search(repo: @repo, query: "is:open", force_pulls: true, force_type: :issues)[:issues]
    assert_empty issues.select { |issue| !issue.pull_request.nil? }
  end

  test "force to issues" do
    issues = Issue::MysqlSearch.search(repo: @repo, query: "is:open", force_type: :issues)[:issues]
    assert_empty issues.select { |issue| !issue.pull_request.nil? }
  end

  test "for queries, state" do
    assert_same_search "is:open"
    assert_same_search "is:closed"
    assert_same_search "state:open"
    assert_same_search "state:closed"
  end

  test "for queries, merge state" do
    assert_same_search "is:merged"
    assert_same_search "is:unmerged"
    assert_same_search "is:unmerged is:closed"
  end

  test "for queries, type" do
    assert_same_search "is:issue"
    assert_same_search "is:pr"
    assert_same_search "type:issue"
    assert_same_search "type:pr"
  end

  test "for queries, sort" do
    assert_same_search "sort:created-asc"
    assert_same_search "sort:created-desc"
    assert_same_search "sort:updated-asc"
    assert_same_search "sort:updated-desc"
    assert_same_search "sort:comments-asc"
    assert_same_search "sort:comments-desc"
    assert_same_search "sort:reactions-smile-desc is:issue"
    assert_same_search "sort:reactions-desc is:issue"
  end

  test "for queries, author" do
    assert_same_search "author:#{@owner}"
    assert_same_search "-author:#{@owner}"
  end

  test "for queries, assignee" do
    assert_same_search "assignee:#{@owner}"
    assert_same_search "-assignee:#{@owner}"
  end

  test "for queries, milestone" do
    assert_same_search "milestone:#{Search::ParsedQuery.encode_value(@milestone.title)}"
    assert_same_search "-milestone:#{Search::ParsedQuery.encode_value(@milestone.title)}"
  end

  test "for queries, label, case insensitive" do
    assert_same_search %Q(label:"#{@label.lowercase_name}")
  end

  test "for queries, label, multiple labels" do
    assert_same_search %Q(label:"#{@label}" label:"#{@emoji_label}")
  end

  test "for queries, mentions" do
    assert_same_search "mentions:#{@owner.login}"
  end

  test "for queries, combinations" do
    assert_same_search "is:open is:issue author:#{@owner} milestone:#{Search::ParsedQuery.encode_value(@milestone.title)}"
    assert_same_search "is:open is:pr no:milestone sort:created-desc"
    assert_same_search "no:milestone no:assignee"
    assert_same_search "no:assignee no:milestone"
  end

  test "optimized labels query", skip_if_feature_disabled: :mysql_search_optimized_label_scope do
    # state
    assert_same_search "is:open"
    assert_same_search "is:closed"
    assert_same_search "state:open"
    assert_same_search "state:closed"

    # merge state
    assert_same_search "is:merged"
    assert_same_search "is:unmerged"
    assert_same_search "is:unmerged is:closed"

    # type
    assert_same_search "is:issue"
    assert_same_search "is:pr"
    assert_same_search "type:issue"
    assert_same_search "type:pr"

    # sort
    assert_same_search "sort:created-asc"
    assert_same_search "sort:created-desc"
    assert_same_search "sort:updated-asc"
    assert_same_search "sort:updated-desc"
    assert_same_search "sort:comments-asc"
    assert_same_search "sort:comments-desc"
    assert_same_search "sort:reactions-smile-desc is:issue"
    assert_same_search "sort:reactions-desc is:issue"

    # author
    assert_same_search "author:#{@owner}"
    assert_same_search "-author:#{@owner}"

    # assignee
    assert_same_search "assignee:#{@owner}"
    assert_same_search "-assignee:#{@owner}"

    # milestone
    assert_same_search "milestone:#{Search::ParsedQuery.encode_value(@milestone.title)}"
    assert_same_search "-milestone:#{Search::ParsedQuery.encode_value(@milestone.title)}"

    # label, case insensitive
    assert_same_search %Q(label:"#{@label.lowercase_name}")

    # label, multiple labels
    assert_same_search %Q(label:"#{@label}" label:"#{@emoji_label}")

    # mentions
    assert_same_search "mentions:#{@owner.login}"

    # combinations
    assert_same_search "is:open is:issue author:#{@owner} milestone:#{Search::ParsedQuery.encode_value(@milestone.title)}"
    assert_same_search "is:open is:pr no:milestone sort:created-desc"
    assert_same_search "no:milestone no:assignee"
    assert_same_search "no:assignee no:milestone"
  end

  test "@me macro is supported searching for issues" do
    # finds the correct issues
    result = Issue::MysqlSearch.search(repo: @repo, query: "author:@me", current_user: @owner)
    assert_equal 2, result[:open_count]
    assert_equal 1, result[:closed_count]
    assert result[:issues].all? { |i| i.user == @owner }
  end

  test "@me macro is supported searching for negative" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "-author:@me", current_user: @owner)
    assert_equal 1, result[:open_count]
    assert_equal 0, result[:closed_count]
    assert result[:issues].all? { |i| i.user != @owner }
  end

  test "@me macro is supported searching for assignee" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "assignee:@me", current_user: @owner)
    assert_equal 2, result[:open_count]
    assert_equal 0, result[:closed_count]
    assert result[:issues].all? { |i| i.assignee == @owner }
  end

  test "@me macro is supported searching for negative assignee" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "-assignee:@me", current_user: @owner)
    assert_equal 1, result[:open_count]
    assert_equal 1, result[:closed_count]
    assert result[:issues].all? { |i| i.assignee != @owner }
  end

  test "@me macro is consistent with elasticsearch" do
    # is consistent with Elasticsearch
    assert_same_search "author:@me", current_user: @owner
    assert_same_search "-author:@me", current_user: @owner

    assert_same_search "assignee:@me", current_user: @owner
    assert_same_search "-assignee:@me", current_user: @owner
  end

  if GitHub.spamminess_check_enabled?
    test "finds open issues of a spammy user using #search" do
      # Spammy user can see their own issues
      result = Issue::MysqlSearch.search(repo: @spammy_repo, current_user: @spammy_user, query: "is:open")
      assert_equal 1, result[:issues].length

      # Other users can't see spammy user's issues
      result = Issue::MysqlSearch.search(repo: @spammy_repo, current_user: nil, query: "is:open")
      assert_equal 0, result[:issues].length
    end

    test "finds open issues of a spammy user using #query_scope" do
      # Spammy user can see their own issues
      result = Issue::MysqlSearch.query_scope(repo: @spammy_repo, current_user: @spammy_user, query: "is:open")
      assert_equal 1, result.length

      # Other users can't see spammy user's issues
      result = Issue::MysqlSearch.query_scope(repo: @spammy_repo, current_user: nil, query: "is:open")
      assert_equal 0, result.length
    end
  end

  def assert_same_search(query, current_user: nil)
    es_results    = Issue::EsSearch.search(repo: @repo, query: query, current_user: current_user)
    mysql_results = Issue::MysqlSearch.search(repo: @repo, query: query, current_user: current_user)

    assert_equal es_results, mysql_results,
      "\n  Elasticsearch results (#{es_results[:issues].size} total) did not match MySQL results (#{mysql_results[:issues].to_a.size} total).\n\n" +
      "    Search Query:      #{query}\n" +
      "    Elasticsearch metadata: Open: #{es_results[:open_count]}, Closed: #{es_results[:closed_count]}\n" +
      "    MySQL metadata: Open: #{mysql_results[:open_count]}, Closed: #{mysql_results[:closed_count]}\n" +
      "    Elasticsearch IDs: #{es_results[:issues].map(&:id).join(',')}\n" +
      "    MySQL IDs:         #{mysql_results[:issues].map(&:id).join(',')}\n\n" +
      "  Full match information:\n\n"
  end
end

class BasicListingForQueryHintsTest < GitHub::TestCase
  def basic_list_query_check(query)
    components = ::Search::Queries::IssueQuery.coerce(query, nil)
    Issue::MysqlSearch.basic_listing?(components)
  end

  test "basic listing" do
    assert basic_list_query_check("is:open")
    assert basic_list_query_check("is:closed")
    assert basic_list_query_check("is:issue")
    assert basic_list_query_check("is:pr")
    assert basic_list_query_check("is:merged")
    assert basic_list_query_check("is:unmerged")
    assert basic_list_query_check("state:open")
    assert basic_list_query_check("state:closed")
    assert basic_list_query_check("type:issue")
    assert basic_list_query_check("type:pr")

    assert basic_list_query_check("state:open type:pr")
    assert basic_list_query_check("state:closed type:issue")
    assert basic_list_query_check("type:issue is:open")
    assert basic_list_query_check("type:pr is:closed")
    assert basic_list_query_check("type:pr is:merged")
    assert basic_list_query_check("type:pr is:unmerged")

    refute basic_list_query_check("searchstring")
    refute basic_list_query_check("author:holman")
    refute basic_list_query_check("label:bug")
    refute basic_list_query_check("milestone:\"Issues 3\"")
    refute basic_list_query_check("assignee:josh")
    refute basic_list_query_check("-assignee:josh")
    refute basic_list_query_check("sort:created-asc")
    refute basic_list_query_check("sort:reactions")
    refute basic_list_query_check("sort:reactions-smile")
    refute basic_list_query_check("no:assignee")
    refute basic_list_query_check("no:milestone")
    refute basic_list_query_check("author:draft")
    refute basic_list_query_check("type:bug")
    refute basic_list_query_check("type:epic,bug is:unmerged")
  end
end

class IsDefaultQueryTest < GitHub::TestCase
  def basic_list_query_check(query)
    parsed_query = ::Search::Queries::IssueQuery.coerce(query, nil)
    ::Search::Queries::IssueQuery.is_default_issues_index_query?(parsed_query)
  end

  test "basic listing" do
    assert basic_list_query_check("is:open is:issue")
    assert basic_list_query_check("is:open is:pr")

    refute basic_list_query_check("is:open is:pr is:issue")
    refute basic_list_query_check("is:closed is:pr")
    refute basic_list_query_check("is:closed is:issue")
    refute basic_list_query_check("searchstring")
    refute basic_list_query_check("author:holman")
    refute basic_list_query_check("label:bug")
    refute basic_list_query_check("milestone:\"Issues 3\"")
    refute basic_list_query_check("assignee:josh")
    refute basic_list_query_check("-assignee:josh")
    refute basic_list_query_check("sort:created-asc")
    refute basic_list_query_check("sort:reactions")
    refute basic_list_query_check("sort:reactions-smile")
    refute basic_list_query_check("no:assignee")
    refute basic_list_query_check("no:milestone")
    refute basic_list_query_check("author:draft")

    refute ::Search::Queries::IssueQuery.is_default_issues_index_query?([])
    refute ::Search::Queries::IssueQuery.is_default_issues_index_query?(nil)
    refute ::Search::Queries::IssueQuery.is_default_issues_index_query?("unparsed query")
  end
end

class CreatedAtQueryTest < GitHub::TestCase
  fixtures do
    @owner     = create(:user)
    @repo      = create(:repository, owner: @owner, from_example: :pull_request_fork)

    issues = T.let([], T::Array[Issue])

    Time.use_zone "Australia/Melbourne" do
      Timecop.freeze(Time.zone.parse("January 01 2020 11:00 AM")) do
        issues << create(:issue, repository: @repo, user: @owner, body: "Issue1")
        T.must(issues.last).update_column(:created_at, 1.day.ago)

        issues << create(:issue, repository: @repo, user: @owner, body: "Issue1")
        T.must(issues.last).update_column(:created_at, 1.day.ago)

        issues << create(:issue, repository: @repo, user: @owner, body: "Issue2")
        T.must(issues.last).update_column(:created_at, 2.days.ago)

        issues << create(:issue, repository: @repo, user: @owner, body: "Issue3")
        T.must(issues.last).update_column(:created_at, 3.days.ago)
      end
    end

    @issues = issues
  end

  test "empty query sort by created_at then id desc" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "")
    assert_equal [@issues[1].id, @issues[0].id, @issues[2].id, @issues[3].id], result[:issues].map { |i| i.id }
  end

  test "sort by most comments fallbacks to id" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "sort:comments-desc")
    assert_equal [@issues[3].id, @issues[2].id, @issues[1].id, @issues[0].id], result[:issues].map { |i| i.id }
  end

  test "sort by created_at then id asc" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "sort:created-desc")
    assert_equal [@issues[1].id, @issues[0].id, @issues[2].id, @issues[3].id], result[:issues].map { |i| i.id }
  end

  test "sort by created_at then id desc" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "sort:created-asc")
    assert_equal [@issues[3].id, @issues[2].id, @issues[0].id, @issues[1].id], result[:issues].map { |i| i.id }
  end

  test "invalid created_at sort option default to desc" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "sort:created-dsc")
    assert_equal [@issues[1].id, @issues[0].id, @issues[2].id, @issues[3].id], result[:issues].map { |i| i.id }
  end

end

class ReasonQueryTest < GitHub::TestCase
  fixtures do
    @owner     = create(:user)
    @repo      = create(:repository, owner: @owner, from_example: :pull_request_fork)


    issues = T.let([], T::Array[Issue])

    issues << create(:issue, repository: @repo, user: @owner, body: "Issue1")
    T.must(issues.last).update_column(:state_reason, nil)

    issues << create(:issue, repository: @repo, user: @owner, body: "Issue2")
    REOPEN_ISSUE_ID = T.must(issues.last).id
    T.must(issues.last).update_column(:state_reason, :reopened)

    issues << create(:issue, repository: @repo, user: @owner, body: "Issue3")
    NOT_PLANNED_ISSUE_ID = T.must(issues.last).id
    T.must(issues.last).update_column(:state, :closed)
    T.must(issues.last).update_column(:state_reason, :not_planned)

    issues << create(:issue, repository: @repo, user: @owner, body: "Issue4")
    COMPLETED_ISSUE_ID = T.must(issues.last).id
    T.must(issues.last).update_column(:state, :closed)
    T.must(issues.last).update_column(:state_reason, nil)

  end

  test "find all issues with state_reason reopened" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue is:open reason:reopened", current_user: @owner)

    assert_equal result[:issues].length, 1
    assert_includes result[:issues].map { |i| i.id }, REOPEN_ISSUE_ID
  end

  test "find all issues with state_reason with space char in state reason" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue is:closed reason:\"not planned\"", current_user: @owner)

    assert_equal result[:issues].length, 1
    assert_includes result[:issues].map { |i| i.id }, NOT_PLANNED_ISSUE_ID
  end

  test "find all completed issues" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue is:closed reason:completed", current_user: @owner)

    assert_equal result[:issues].length, 1
    assert_includes result[:issues].map { |i| i.id }, COMPLETED_ISSUE_ID
  end

  test "return all issues if state_reason is invalid" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue reason:random", current_user: @owner)
    assert_equal result[:issues].length, 4
  end

  test "query for all issues with no state filter with state reason not planned" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue reason:\"not planned\"", current_user: @owner)

    assert_equal result[:issues].length, 1
    assert_includes result[:issues].map { |i| i.id }, NOT_PLANNED_ISSUE_ID
  end

  test "query for all issues with no state filter with state reason not completed" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue reason:completed", current_user: @owner)

    assert_equal result[:issues].length, 1
    assert_includes result[:issues].map { |i| i.id }, COMPLETED_ISSUE_ID
  end

  test "return no issue for invalid state and state_reason combination" do
    [
      "is:issue is:open reason:completed",
      "is:issue is:closed reason:reopened",
      "is:issue is:open reason:\"not planned\""
    ].each do |query|
      result = Issue::MysqlSearch.search(repo: @repo, query: query, current_user: @owner)
      assert_equal result[:issues].length, 0
    end
  end
end

class MentionedQueryTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)

    @mentionee = create(:user)
    @repo.add_member @mentionee
    only_jobs = [SubscribeAndNotifyJob]

    mentioned_issue = perform_enqueued_jobs(only: only_jobs) do
      create :issue, repository: @repo, user: @owner, body: "hey @#{@mentionee.login}"
    end

    other_mentioned_issue = perform_enqueued_jobs(only: only_jobs) do
      create :issue, repository: @repo, user: @owner, body: "hey @#{@mentionee.login}"
    end

    @mentioned_issues = [mentioned_issue, other_mentioned_issue]
  end

  test "can search for mentions" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue mentions:#{@mentionee}", current_user: @owner)

    assert_equal 2, result[:open_count]
    assert_equal 0, result[:closed_count]
    assert_same_elements result[:issues].map(&:id), @mentioned_issues.map(&:id)
  end
end

class TypeQueryTest < GitHub::TestCase
  fixtures do
    enable_feature_flag(:issue_types)
    @owner = create :user, plan: "large"
    @org = create :organization, admin: @owner, plan: "bronze"
    @repo = create(:private_repository, owner: @org)
    @first_issue_type = @org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
    @second_issue_type = @org.issue_types.find_by(name: IssueType::DEFAULTS.second[:name])
    @issue_with_first_type_a = create :issue, repository: @repo, user: @owner, issue_type: @first_issue_type
    @issue_with_first_type_b = create :issue, repository: @repo, user: @owner, issue_type: @first_issue_type
    @issue_with_second_type = create :issue, repository: @repo, user: @owner, issue_type: @second_issue_type
    @issue_with_no_type = create :issue, repository: @repo, user: @owner
    @pr = create :pull_request, :disable_disk_access, repository: @repo, user: @owner
  end

  setup do
    enable_feature_flag(:issue_types)
    enable_feature_flag(:prefill_issue_types)
    enable_feature_flag(:issue_types_update_api_hash)
  end

  test "ignores issue type search if issue_types is disabled" do
    disable_feature_flag(:issue_types)
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue type:#{@first_issue_type.name}", current_user: @owner)
    assert_equal result[:issues].length, 4
  end

  test "ignores issue type search if prefill_issue_types is disabled" do
    disable_feature_flag(:prefill_issue_types)
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue type:#{@first_issue_type.name}", current_user: @owner)
    assert_equal result[:issues].length, 4
  end

  test "ignores issue type search if issue_types_update_api_hash is disabled" do
    disable_feature_flag(:issue_types_update_api_hash)
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue type:#{@first_issue_type.name}", current_user: @owner)
    assert_equal result[:issues].length, 4
  end

  test "ignores issue type search if :force_type is :pull_requests" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "type:#{@first_issue_type.name}", current_user: @owner, force_type: :pull_requests)
    assert_equal result[:issues].length, 1
    assert_includes result[:issues].map { |i| i.id }, @pr.issue.id
  end

  test "returns no issues if type is not recognized" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue type:asdf", current_user: @owner)
    assert_equal result[:issues].length, 0
  end

  test "returns no issues if issue type is disabled" do
    @first_issue_type.update!(enabled: false)
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue type:#{@first_issue_type.name}", current_user: @owner)
    assert_equal result[:issues].length, 0
  end

  test "returns no issues if type is private and repo is public" do
    public_repository = create(:public_repository, owner: @org)
    public_issue = create :issue, repository: public_repository, user: @owner, issue_type: @first_issue_type
    @first_issue_type.update!(private: true)
    result = Issue::MysqlSearch.search(repo: public_repository, query: "is:issue type:#{@first_issue_type.name}", current_user: @owner)
    assert_equal result[:issues].length, 0
  end

  test "returns issues with private type if repo is private" do
    private_repository = create(:private_repository, owner: @org)
    private_issue = create :issue, repository: private_repository, user: @owner, issue_type: @first_issue_type
    @first_issue_type.update!(private: true)
    result = Issue::MysqlSearch.search(repo: private_repository, query: "is:issue type:#{@first_issue_type.name}", current_user: @owner)
    assert_equal result[:issues].length, 1
    assert_includes result[:issues].map { |i| i.id }, private_issue.id
  end

  test "returns multiple issues matching type" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue type:#{@first_issue_type.name}", current_user: @owner)
    assert_equal result[:issues].length, 2
  end

  test "returns issues matching any type" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue type:*", current_user: @owner)
    assert_equal result[:issues].length, 3
  end

  test "returns issues with no type" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue type:none", current_user: @owner)
    assert_equal result[:issues].length, 0
  end

  test "doesn't support no:type if issue types is disabled" do
    disable_feature_flag(:issue_types)
    result = Issue::MysqlSearch.search(repo: @repo, query: "is:issue type:none", current_user: @owner)
    assert_equal result[:issues].length, 4
  end

  test "doesn't support no:type if :force_type is pull request" do
    result = Issue::MysqlSearch.search(repo: @repo, query: "no:type", current_user: @owner, force_type: :pull_requests)
    assert_equal result[:issues].length, 1
    assert_includes result[:issues].map { |i| i.id }, @pr.issue.id
  end
end
