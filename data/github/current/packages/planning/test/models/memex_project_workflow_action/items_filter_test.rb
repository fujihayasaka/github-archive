# typed: true
# frozen_string_literal: true

require "test_helper"
require "csv"

class MemexProjectWorkflowItemsFilterTest < GitHub::TestCase

  fixtures do
    GitHub.flipper[:issue_types].enable
    @user = create(:user, login: "user1")
    @org = create(:organization)
    @org.add_member(@user)
    repo = create(:repository, owner: @org)
    @project = create(:memex_project, owner: @org)
    @label = create(:label, name: "bug", repository: repo)
    @milestone = create(:milestone, title: "one", repository: repo)
    @issue_type = @org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])

    @data = {
      draft_issue: create(:draft_issue, assignees: [@user], title: "possibly a bug").freeze,
      draft_pr: create(:pull_request, :disable_disk_access, repository: repo, user: @user, draft: true, head_ref: "ref0", labels: [@label], assignees: [@user], milestone: @milestone, title: "potential -fix").freeze,
      open_issue: create(:issue, repository: repo, state: "open", labels: [@label], assignees: [@user], milestone: @milestone, issue_type: @issue_type, title: "definitely a bug").freeze,
      open_pr: create(:pull_request, :disable_disk_access, repository: repo, user: @user, labels: [@label], assignees: [@user], milestone: @milestone, title: "[a finished fix").freeze,
      closed_issue: create(:issue, repository: repo, state: "closed", state_reason: :not_planned, labels: [@label], assignees: [@user], milestone: @milestone, title: "resolved: -bug").freeze,
      closed_pr: create(:pull_request, :closed, :disable_disk_access, repository: repo, user: @user, head_ref: "ref1", labels: [@label], assignees: [@user], milestone: @milestone, title: "not the right fix").freeze,
      merged_pr: create(:pull_request, :merged, :disable_disk_access, repository: repo, user: @user, head_ref: "ref2", labels: [@label], assignees: [@user], milestone: @milestone, title: "shipped a fix").freeze
    }.freeze
  end

  def item_to_datakey(item)
    @data.entries.find { |_k, v| v.id == item.id }.first
  end

  def pretty_print(items)
    items.map { |item| item_to_datakey(item) }.join(", ")
  end

  def print_error_message(expected, items, query)
    expected = expected.to_set
    items = items.to_set
    missing_items = pretty_print expected - items
    present_items = pretty_print items - expected
    <<~ERROR
    Query `#{query}` filters items incorrectly.
    #{ "- should return:#{missing_items}" if missing_items.present? }
    #{ "+ should not return: #{present_items}" if present_items.present? }
    ERROR
  end

  class TestItem
    def initialize(open, title = "")
      @open = open
      @title = title
    end

    def open?
      @open
    end

    def pull_request?
      false
    end

    def title
      @title
    end
  end

  class TestPullRequest
    def initialize(open)
      @open = open
    end

    def open?
      @open
    end

    def closed?
      !@open
    end

    def merged?
      !@open
    end

    def pull_request?
      true
    end
  end

  context "filter_tokens" do
    test "returns [] when no query specified" do
      query = []
      expected = []

      output = MemexProjectWorkflowAction::ItemsFilter.new.filter_tokens(query)
      assert_equal expected, output
    end

    test "returns correct tokens when correct query is specified" do
      query = [
        { keyword: :is, values: ["closed"], exclude: false },
        { keyword: :"last-updated", values: ["1day"], exclude: false }
      ]
      expected = [
        { keyword: :is, values: ["closed"], exclude: false },
        { keyword: :"last-updated", values: ["1day"], exclude: false }
      ]

      output = MemexProjectWorkflowAction::ItemsFilter.new.filter_tokens(query)
      assert_equal expected, output
    end

    test "filters out incorrect tokens" do
      query = [
        { keyword: :is, values: ["closed"], exclude: false },
        { keyword: :is, values: ["something"], exclude: false },
      ]
      expected = [{ keyword: :is, values: ["closed"], exclude: false }]

      output = MemexProjectWorkflowAction::ItemsFilter.new.filter_tokens(query)
      assert_equal expected, output
    end

    test "filters out incorrect tokens with multivalues" do
      query = [
        { keyword: :is, values: %w[issue closed], exclude: false },
        { keyword: :reason, values: ["not planned", "something"], exclude: false }
      ]
      expected = [
        { keyword: :is, values: %w[issue closed], exclude: false },
        { keyword: :reason, values: ["not planned"], exclude: false }
      ]

      output = MemexProjectWorkflowAction::ItemsFilter.new.filter_tokens(query)
      assert_equal expected, output
    end
  end

  context "validate_tokens" do
    test "returns true for valid tokens" do
      tokens = [
        { keyword: :is, values: ["closed"], exclude: false },
        { keyword: :"last-updated", values: ["1day"], exclude: false }
      ]

      expected = {
        valid: true,
        invalid_tokens: []
      }

      result = MemexProjectWorkflowAction::ItemsFilter.validate_tokens(tokens)

      assert_equal expected, result
    end

    test "returns false for invalid tokens" do
      tokens = [
        { keyword: :is, values: ["closed"], exclude: false },
        { keyword: :"bad-keyword", values: ["foobar"], exclude: false }
      ]

      expected = {
        valid: false,
        invalid_tokens: [
          { keyword: :"bad-keyword", values: ["foobar"], exclude: false }
        ]
      }

      result = MemexProjectWorkflowAction::ItemsFilter.validate_tokens(tokens)
      assert_equal expected, result
    end

    test "returns false for invalid values" do
      tokens = [
        { keyword: :is, values: ["spaceship"], exclude: false }
      ]

      expected = {
        valid: false,
        invalid_tokens: [
          { keyword: :is, values: ["spaceship"], exclude: false }
        ]
      }

      result = MemexProjectWorkflowAction::ItemsFilter.validate_tokens(tokens)
      assert_equal expected, result
    end
  end

  context "filter_items" do
    test "filter correct items" do
      query = "is:closed"

      item = TestItem.new(false)
      expected = [item]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([item, TestItem.new(true)], query)
      assert_equal expected, output
    end

    test "handles empty queries" do
      query = ""

      item = TestItem.new(false)
      expected = [item]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([item], query)
      assert_equal expected, output
    end

    test "filters correct items with the last-updated query" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      query = "last-updated:1day"

      issue1 = create(:issue, repository: repo, state: "closed", updated_at: 3.days.ago)
      issue2 = create(:issue, repository: repo, state: "closed", updated_at: 1.minute.ago)

      expected = [issue1]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([issue1, issue2], query, memex_project_owner: org)

      assert_equal expected, output
    end

    test "filters correct items with the -last-updated query" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      query = "-last-updated:2days"

      issue1 = create(:issue, repository: repo, state: "closed", updated_at: 3.days.ago)
      issue2 = create(:issue, repository: repo, state: "open", updated_at: 1.minute.ago)

      expected = [issue2]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([issue1, issue2], query, memex_project_owner: org)

      assert_equal expected, output
    end

    test "filters correct items with the updated query" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      query = "updated:<@today-1m"

      issue1 = create(:issue, repository: repo, state: "closed", updated_at: 2.months.ago)
      issue2 = create(:issue, repository: repo, state: "closed", updated_at: 1.day.ago)

      expected = [issue1]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([issue1, issue2], query, memex_project_owner: org)

      assert_equal expected, output
    end

    test "filters correct items with the -updated query" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      query = "-updated:<@today-2w"

      issue1 = create(:issue, repository: repo, state: "closed", updated_at: 3.weeks.ago)
      issue2 = create(:issue, repository: repo, state: "closed", updated_at: 1.week.ago)

      expected = [issue2]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([issue1, issue2], query, memex_project_owner: org)

      assert_equal expected, output
    end

    test "return multiple correct items" do
      query = "is:closed"

      item1 = TestItem.new(false)
      item2 = TestItem.new(false)
      item3 = TestItem.new(true)
      expected = [item1, item2]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([item1, item2, item3], query)
      assert_equal expected, output
    end

    test "return results for several tokens" do
      query = "is:issue is:closed"

      item1 = TestItem.new(true)
      item2 = TestItem.new(false)
      item3 = TestItem.new(true)
      item4 = TestPullRequest.new(true)
      expected = [item2]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([item1, item2, item3, item4], query)
      assert_equal expected, output
    end

    test "return multiple correct items with multivalues" do
      query = "is:pr,closed"

      item1 = TestItem.new(false)
      item2 = TestItem.new(false)
      item3 = TestItem.new(true)
      item4 = TestPullRequest.new(true)
      expected = [item1, item2, item4]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([item1, item2, item3, item4], query)
      assert_equal expected, output
    end

    test "return multiple correct items including title" do
      query = "is:open is:something [bug]"

      item1 = TestItem.new(true, "[bug] a bug")
      item2 = TestItem.new(true, "[bug] some other issue")
      item3 = TestItem.new(true, "[bug] and another one")
      item4 = create(
        :memex_project_item,
        content: create(:issue, state: "open", title: "[bug] in project item content")
      )

      input = [item1, item2, item3, item4]
      output = MemexProjectWorkflowAction::ItemsFilter.filter_items(input, query)

      expected = [item1, item2, item3, item4]
      assert_equal expected, output
    end

    test "return multiple correct items including title any order" do
      query = "is:open is:something bug fix"

      item1 = TestItem.new(true, "[bug] fixing a bug")
      item2 = TestItem.new(true, "[fix] possibly a bug")
      item3 = TestItem.new(true, "[chat] bug fixes 101")
      item4 = TestItem.new(true, "[bug] just a bug") # should be ignored
      item5 = create(:memex_project_item) # should be ignored

      input = [item1, item2, item3, item4, item5]
      output = MemexProjectWorkflowAction::ItemsFilter.filter_items(input, query)

      expected = [item1, item2, item3]
      assert_equal expected, output
    end

    test "handles assignee query" do
      query = "assignee:user1"
      key = :draft_pr
      expected = [@data[key]]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([@data[key]], query)
      assert_equal expected, output
    end

    test "handles assignee query with leading @" do
      query = "assignee:@user1"
      key = :draft_pr
      expected = [@data[key]]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([@data[key]], query)
      assert_equal expected, output
    end

    test "handles assignees query with leading @s" do
      draft_issue = create(:draft_issue, assignees: [create(:verified_user, login: "user2")], title: "possibly a bug").freeze

      query = "assignee:@user1,@user2"
      expected = [@data[:draft_pr], draft_issue]

      input = [
        create(:draft_issue),
        create(:draft_issue),
        @data[:draft_pr],
        draft_issue
      ]

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items(input, query)
      assert_same_elements expected, output
    end

    test "handles `no` query" do
      repo = create(:repository, owner: @org, admin: @user)
      issue = create(:issue, repository: repo, assignees: [], labels: [])
      issue_with_reason = create(:issue, repository: repo, state: "closed", state_reason: "not_planned", assignees: [], labels: [])
      issue_with_assignee = create(:issue, repository: repo, assignees: [@user], labels: [])
      issue_with_label = create(:issue, repository: repo, assignees: [], labels: [create(:label, repository: repo)])
      issue_with_issue_type = create(:issue, repository: repo, assignees: [], labels: [], issue_type: @issue_type)

      {
        "no:assignee" => [issue, issue_with_reason, issue_with_label, issue_with_issue_type],
        "no:label" => [issue, issue_with_reason, issue_with_assignee, issue_with_issue_type],
        "no:reason" => [issue, issue_with_assignee, issue_with_label, issue_with_issue_type],
        "no:type" => [issue, issue_with_assignee, issue_with_label, issue_with_reason]

      }.each do |query, expected|
        output = MemexProjectWorkflowAction::ItemsFilter.filter_items(
          [issue, issue_with_reason, issue_with_assignee, issue_with_label, issue_with_issue_type],
          query
        )

        assert_same_elements expected, output, "Testing: #{query}"
      end
    end

    test "handles `has` query" do
      repo = create(:repository, owner: @org, admin: @user)
      issue = create(:issue, repository: repo, assignees: [], labels: [])
      issue_with_reason = create(:issue, repository: repo, state: "closed", state_reason: "not_planned", assignees: [], labels: [])
      issue_with_assignee = create(:issue, repository: repo, assignees: [@user], labels: [])
      issue_with_label = create(:issue, repository: repo, assignees: [], labels: [create(:label, repository: repo)])
      issue_with_issue_type = create(:issue, repository: repo, assignees: [], labels: [], issue_type: @issue_type)
      issue_with_milestone = create(:issue, repository: repo, milestone: create(:milestone, repository: repo))

      {
        "has:assignee" => [issue_with_assignee],
        "has:label" => [issue_with_label],
        "has:reason" => [issue_with_reason],
        "has:type" => [issue_with_issue_type],
        "has:milestone" => [issue_with_milestone],
      }.each do |query, expected|
        output = MemexProjectWorkflowAction::ItemsFilter.filter_items(
          [issue, issue_with_reason, issue_with_assignee, issue_with_label, issue_with_issue_type, issue_with_milestone],
          query
        )

        assert_same_elements expected, output, "Testing: #{query}"
      end
    end

    test "handles missing project item content gracefully" do
      query = "is:open"

      empty_project_item = create(:memex_project_item, :skip_validation, content: nil)

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([empty_project_item], query)
      assert_empty output
    end

    test "handles issues with no milestones for milestone query gracefully" do
      query = "is:issue,pr milestone:foo"

      repo = create(:repository, owner: @user)
      issue = create(:issue, repository: repo)

      output = MemexProjectWorkflowAction::ItemsFilter.filter_items([issue], query)
      assert_empty output
    end

    context "performance" do
      test "efficiently loads data for is:pr grammar checks" do
        query = "is:pr"

        issues = 3.times.map { create(:issue, repository: create(:repository, owner: @user)) }
        prs = 3.times.map do
          repo = create(:repository, owner: @user)
          create(:pull_request, :disable_disk_access, repository: repo).reload
        end

        project_items = 3.times.map do
          repo = create(:repository, owner: @user)
          create(:memex_project_item, content: create(:issue, repository: repo)).reload
        end +
        3.times.map do
          repo = create(:repository, owner: @user)
          create(:memex_project_item, content: create(:pull_request, :disable_disk_access, repository: repo)).reload
        end

        # 1 query for loading all issue.pull_request
        assert_max_query_count(1, ignore_feature_flags: true, backtrace_lines: 5) do
          MemexProjectWorkflowAction::ItemsFilter.filter_items(issues + prs, query)
        end

        # 1 query to load the 3 issues project_item.content
        # 1 query to load the 3 pull requests project_item.content
        # 1 query to load the 3 issues backing the pull requests content
        assert_max_query_count(3, ignore_feature_flags: true, backtrace_lines: 5) do
          MemexProjectWorkflowAction::ItemsFilter.filter_items(project_items, query)
        end
      end

      test "efficiently loads data for assignee: grammar checks" do
        query = "is:issue,pr assignee:user1"

        issues = 3.times.map do
          repo = create(:repository, owner: @user)
          assignees = 3.times.map { create(:user) }
          assignees.each { |user| repo.add_member(user) }
          create(:issue, repository: repo, assignees: assignees).reload
        end

        prs = 3.times.map do
          repo = create(:repository, owner: @user)
          assignees = 3.times.map { create(:user) }
          assignees.each { |user| repo.add_member(user) }
          create(:pull_request, :disable_disk_access, repository: repo, assignees: assignees).reload
        end

        project_items = 3.times.map do
          repo = create(:repository, owner: @user)
          assignees = 3.times.map { create(:user) }
          assignees.each { |user| repo.add_member(user) }
          create(:memex_project_item, content: create(:issue, repository: repo, assignees: assignees).reload).reload
        end +
        3.times.map do
          repo = create(:repository, owner: @user)
          assignees = 3.times.map { create(:user) }
          assignees.each { |user| repo.add_member(user) }
          create(:memex_project_item, content: create(:pull_request, :disable_disk_access, repository: repo, assignees: assignees).reload).reload
        end

        # 1 query for loading all issue assignements
        # 1 query for loading all issue assignements users
        # 1 query for loading all pr.issue
        # 1 query for loading all pr.issue assignements
        # 1 query for loading all pr.issue assignements users
        # 1 query for loading query user by login
        assert_max_query_count(6, ignore_feature_flags: true, backtrace_lines: 5) do
          MemexProjectWorkflowAction::ItemsFilter.filter_items(issues + prs, query)
        end

        # 1 query to load the 3 issues project_item.content
        # 1 query to load the 3 pull_request project_item.content
        # 1 query to load the issue assignments
        # 1 query to load the issue assignments users
        # 1 query to load the 3 issues backing the pull request content
        # 1 query to load the 3 pull request content assignments
        # 1 query to load the 3 pull request content assignment users
        # 1 query for loading query user by login
        assert_max_query_count(8, ignore_feature_flags: true, backtrace_lines: 5) do
          MemexProjectWorkflowAction::ItemsFilter.filter_items(project_items, query)
        end
      end

      test "efficiently loads data for label: grammar checks" do
        query = "is:issue,pr label:bug"

        issues = 3.times.map do
          repo = create(:repository, owner: @user)
          labels = 3.times.map { create(:label, repository: repo) }
          create(:issue, repository: repo, labels: labels).reload
        end

        prs = 3.times.map do
          repo = create(:repository, owner: @user)
          labels = 3.times.map { create(:label, repository: repo) }
          create(:pull_request, :disable_disk_access, repository: repo, labels: labels).reload
        end

        project_items = 3.times.map do
          repo = create(:repository, owner: @user)
          labels = 3.times.map { create(:label, repository: repo) }
          create(:memex_project_item, content: create(:issue, repository: repo, labels: labels).reload).reload
        end +
        3.times.map do
          repo = create(:repository, owner: @user)
          labels = 3.times.map { create(:label, repository: repo) }
          create(:memex_project_item, content: create(:pull_request, :disable_disk_access, repository: repo, labels: labels).reload).reload
        end

        # 1 query for loading all issues_labels for issues
        # 1 query for loading all labels for issues
        # 1 query for loading all issues for prs
        # 1 query for loading all issues_labels for pr.issues
        # 1 query for loading all labels for pr.issues
        assert_max_query_count(5, ignore_feature_flags: true, backtrace_lines: 5) do
          MemexProjectWorkflowAction::ItemsFilter.filter_items(issues + prs, query)
        end

        # 1 query for loading issues project_item.content
        # 1 query for loading prs project_item.content
        # 1 query for loading all issues_labels for issues
        # 1 query for loading all labels for issues
        # 1 query for loading all issues for prs
        # 1 query for loading all issues_labels for pr.issues
        # 1 query for loading all labels for pr.issues
        assert_max_query_count(7, ignore_feature_flags: true, backtrace_lines: 5) do
          MemexProjectWorkflowAction::ItemsFilter.filter_items(project_items, query)
        end
      end

      test "efficiently loads data for milestone: grammar checks" do
        query = "is:issue,pr milestone:foo"

        issues = 3.times.map do
          repo = create(:repository, owner: @user)
          milestone = create(:milestone, repository: repo)
          create(:issue, repository: repo, milestone: milestone).reload
        end

        prs = 3.times.map do
          repo = create(:repository, owner: @user)
          milestone = create(:milestone, repository: repo)
          create(:pull_request, :disable_disk_access, repository: repo, milestone: milestone).reload
        end

        project_items = 3.times.map do
          repo = create(:repository, owner: @user)
          milestone = create(:milestone, repository: repo)
          create(:memex_project_item, content: create(:issue, repository: repo, milestone: milestone).reload).reload
        end +
        3.times.map do
          repo = create(:repository, owner: @user)
          milestone = create(:milestone, repository: repo)
          create(:memex_project_item, content: create(:pull_request, :disable_disk_access, repository: repo, milestone: milestone).reload).reload
        end

        # 1 query for loading all milestones for issues
        # 1 query for loading all issues for prs
        # 1 query for loading all milestones for pr.issues
        assert_max_query_count(3, ignore_feature_flags: true, backtrace_lines: 5) do
          MemexProjectWorkflowAction::ItemsFilter.filter_items(issues + prs, query)
        end

        # 1 query for loading issues project_item.content
        # 1 query for loading prs project_item.content
        # 1 query for loading all milestones for issues
        # 1 query for loading all issues for prs
        # 1 query for loading all milestones for pr.issues
        assert_max_query_count(5, ignore_feature_flags: true, backtrace_lines: 5) do
          MemexProjectWorkflowAction::ItemsFilter.filter_items(project_items, query)
        end
      end

      test "efficiently loads data for type: grammar checks" do
        query = "is:issue type:foo"

        issues = 3.times.map do
          org = create(:organization)
          repo = create(:repository, owner: org)
          issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])

          create(:issue, repository: repo, issue_type: issue_type)
        end

        # 1 query for loading all issue issue_types
        # 1 query for loading all issue issue_types repository_issue_types
        assert_max_query_count(2, ignore_feature_flags: true, backtrace_lines: 5) do
          MemexProjectWorkflowAction::ItemsFilter.filter_items(issues, query)
        end
      end
    end
  end

  context "filter_items should return correct issues/pull requests for a given query" do

    # this table will be used to generate tests
    # the headers should match @data fields names
    # each test will be generated for a single row in CSV table
    matrix = <<~CSV
      query,               draft_issue,   draft_pr, open_issue, open_pr, closed_issue, closed_pr, merged_pr
      is:open,                      ✅,         ✅,         ✅,      ✅,             ,          ,
      is:draft,                     ✅,         ✅,           ,        ,             ,          ,
      is:pr,                          ,         ✅,           ,      ✅,             ,        ✅,        ✅
      is:issue,                     ✅,           ,         ✅,        ,           ✅,          ,
      is:closed,                      ,           ,           ,        ,           ✅,        ✅,        ✅
      is:merged,                      ,           ,           ,        ,             ,          ,        ✅
      label:bug,                      ,          ✅,         ✅,      ✅,           ✅,        ✅,        ✅
      assignee:user1,               ✅,         ✅,          ✅,      ✅,           ✅,        ✅,        ✅
      milestone:one,                  ,         ✅,          ✅,      ✅,           ✅,        ✅,        ✅
      type:task,                      ,          ,          ✅,       ,               ,         ,
      reason:"not planned",           ,           ,           ,        ,           ✅,         ,
      bug,                          ✅,          ,           ✅,        ,           ✅,          ,
      fix,                           ,          ✅,          ,       ✅,             ,         ✅,      ✅
      updated:<@today-1d              ,          ,           ,         ,            ,          ,         ,
      no:label,                     ✅,          ,           ,        ,             ,          ,
      no:assignee,                    ,          ,           ,        ,             ,          ,
      no:milestone,                 ✅,          ,           ,        ,             ,          ,
      no:type,                      ✅,         ✅,           ,      ✅,           ✅,         ✅,       ✅
      no:reason,                    ✅,         ✅,         ✅,      ✅,             ,        ✅,        ✅
      `is:open,closed`,             ✅,         ✅,         ✅,      ✅,           ✅,        ✅,        ✅
      `is:merged,closed`,             ,           ,           ,        ,           ✅,        ✅,        ✅
      -is:open,                       ,           ,           ,        ,           ✅,        ✅,        ✅
      -is:draft,                      ,           ,         ✅,      ✅,           ✅,        ✅,        ✅
      -is:pr,                       ✅,           ,         ✅,        ,           ✅,          ,
      -is:merged,                   ✅,         ✅,         ✅,      ✅,           ✅,        ✅,
      -is:issue,                      ,         ✅,           ,      ✅,             ,        ✅,        ✅
      -is:closed,                   ✅,         ✅,         ✅,      ✅,             ,          ,
      `-is:open,closed`,              ,           ,           ,        ,             ,          ,
      `-is:open,merged`,              ,           ,           ,        ,           ✅,        ✅,
      `-is:merged,closed`,          ✅,         ✅,         ✅,      ✅,             ,          ,
      `-last-updated:3days`,        ✅,         ✅,         ✅,      ✅,           ✅,        ✅,        ✅
      -label:bug,                   ✅,          ,           ,        ,             ,          ,
      -assignee:user1,                ,          ,           ,        ,             ,          ,
      -milestone:one,               ✅,          ,           ,        ,             ,          ,
      -type:task,                   ✅,         ✅,           ,      ✅,           ✅,         ✅,       ✅
      -reason:"not planned",        ✅,         ✅,         ✅,      ✅,             ,         ✅,       ✅
      -fix,                           ,         ✅,           ,         ,              ,          ,
      -bug,                           ,          ,            ,         ,            ✅,         ,
      -updated:<@today-1d,          ✅,         ✅,           ✅,      ✅,            ✅,        ✅,      ✅
    CSV

    tests = CSV.parse(matrix,
      headers: true,
      strip: true,
      quote_char: "`",
      header_converters: :symbol,
      converters: ->(item) { if item == "✅"
                               true
                             else
                               item.present? ? item : false
                             end
                  })

    raise "Expected parsed CSV table" unless tests.is_a?(CSV::Table)

    tests.each do |row|
      count = row.count { |v| v.last == true }

      test "filter_items with query #{row[:query]} returns #{count} items" do

        # all tests have the same input dataset based on headers (except the :query)
        input = T.must(tests.headers[1..tests.headers.size]).map do |header|
          @data[header]
        end

        query = row[:query]

        # generate the expected output based on the corresponding row from CSV
        expected = input.select.with_index do |_item, index|
          row[index + 1]
        end

        output = MemexProjectWorkflowAction::ItemsFilter.filter_items(input, query, memex_project_owner: @project.owner)

        assert_equal expected, output, print_error_message(expected, output, query)
      end
    end
  end
end
