# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/planning"
require "test_helpers/spokesd"

class MemexProjectItemPrefillerTest < GitHub::TestCase
  include IssuesGraphTestHelpers
  include SubIssuesHelpers

  fixtures do
    Spokesd.enable_spokesd
    GitHub.flipper[:tasklist_block].disable
    GitHub.flipper[:issues_graph_api_concurrent_faraday].disable
    GitHub.flipper[:issue_hierarchy_state].disable
    GitHub.flipper[:hierarchy_cache_key].disable
    GitHub.flipper[:tasklist_block_markdown_at_rest].disable
    GitHub.flipper[:project_hierarchy_columns].enable
    GitHub.flipper[:issues_graph_api_disable_denormalized_read].disable
    GitHub.flipper[:memex_increased_issues_graph_timeouts].disable
    GitHub.flipper[:sub_issues].enable
    GitHub.flipper[:issue_types].enable

    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @org_members = 5.times.map do
      u = create(:verified_user)
      create(:primary_avatar, owner: u, updater: u)
      @org.add_member(u)
      u
    end

    @memex = create(:memex_project, owner: @org)
    @text_column = create(
      :memex_project_column,
      user_defined: true,
      data_type: :text,
      memex_project: @memex
    )
    @memex.reload # Make sure we reset the @memex.columns store.

    @repo = create(:private_repository, owner: @org, from_example: :repository_test_simple)
    @repo.update!(labels: [
      create(:label, name: "bug :bug:", repository: @repo),
      create(:label, name: "enhancement :sparkles:", repository: @repo),
    ])
    @repo_labels = @repo.labels.all.to_a
    @milestones = create_list(:milestone, 2, repository: @repo)

    @repo2 = create(:private_repository, owner: @org, from_example: :repository_test_simple)

    5.times do |n|
      item = @memex.build_item(creator: @admin, draft_issue_title: "rough idea ##{n}")
      item.set_column_value(@text_column, "foo", @admin)
      item.save!
    end

    @milestone_column = @memex.columns.find(&:milestone?)

    5.times do |n|
      issue = create(:issue, repository: @repo, user: @admin)
      issue.add_assignees([@org_members[n - 1]])
      issue.add_labels(@repo_labels[n % 2])
      milestone = @milestones[n % 2]
      issue.update!(milestone: milestone)
      item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: issue)
      item.set_column_value(@text_column, "bar", @admin)
      create(
        :memex_project_column_value,
        json_value: {
          type: "Milestone",
          value: milestone.memex_column_hash
        },
        memex_project_column_id: @milestone_column.id,
        memex_project_item_id: item.id
      )
    end

    5.times do |n|
      pull = create(
        :pull_request,
        :disable_disk_access,
        repository: @repo,
        user: @admin,
        head_ref: "ref-#{SecureRandom.hex(6)}"
      )
      pull.issue.add_assignees([@org_members[n - 1]])
      pull.request_review_from(actor: @admin, reviewers: [@org_members[(n + 4) % 5]])
      pull.issue.add_labels(@repo_labels[n % 2])
      milestone = @milestones[n % 2]
      pull.issue.update!(milestone: milestone)
      item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: pull)
      item.set_column_value(@text_column, "baz", @admin)
      create(
        :memex_project_column_value,
        json_value: {
          type: "Milestone",
          value: milestone.memex_column_hash
        },
        memex_project_column_id: @milestone_column.id,
        memex_project_item_id: item.id
      )
    end

    # 5 archived items, archived by 5 different users
    5.times do |n|
      issue = create(:issue, repository: @repo, user: @admin)
      item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: issue, archived_at: DateTime.now, archiver: @org_members[n - 1])
    end
  end

  setup do
    Spokesd.enable_spokesd
    mock_issues_graph_client

    @default_columns = MemexProjectColumn.default_columns
  end

  test "prefills draft issue content efficiently" do
    # Make sure that we actually attempt to serialize several columns.
    assert @memex.columns.length > 1

    assert_max_query_count_per_table({ draft_issues: 1, memex_project_column_values: 1 }) do
      MemexProjectItemPrefiller.new(
        @memex.memex_project_items,
        columns: @memex.columns
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      @memex.memex_project_items.map { |i| i.to_hash(columns: @default_columns) }
    end
  end

  test "prefills issue and pull request content efficiently" do
    # Make sure that we actually attempt to serialize several columns.
    assert @memex.columns.length > 1

    project_items = @memex.memex_project_items.reject(&:archived?)

    total_query_count = assert_max_query_count_per_table({
      # One query for loading memex_project_item.content, and a second for loading all the issues
      # associated with items where content_type == 'PullRequest'.
      issues: 2,

      # One query for loading the users for assignments, one for reviewers, one
      # for pull request authors, two for loading the repo owners, one for tracked_by_items.
      users: 6,

      # One query for assignee primary avatars and the other for the reviewer primary avatars.
      primary_avatars: 2,

      # For everything else we expect just one query.
      pull_requests: 1,
      assignments: 1,
      issue_next_assignments: 1,
      issue_types: 1,
      repository_issue_types: 1,
      issues_labels: 1,
      labels: 1,
      milestones: 1,
      repositories: 1,
      memex_project_column_values: 1,
      close_issue_references: 1,
      review_requests: 1,
      pull_request_reviews: 1,
      pull_request_reviews_review_requests: 1,
      sub_issues: 1,
      sub_issue_lists: 1,
      draft_issues: 1,
    }) do
      count_queries(ignore_feature_flags: true) do
        MemexProjectItemPrefiller.new(project_items, columns: @memex.columns).prefill

        # Call some methods that would result in database access if the prefiller didn't do its job.
        project_items.map { |i| i.to_hash(columns: @memex.columns) }
      end
    end

    # Finally, make sure this test explicitly accounts for all queries.
    # Note: there is an extra one for  pull request review requests
    assert_equal 26, total_query_count, "issued too many queries in total"
  end

  test "limits number of pull request IDs in WHERE...IN clauses" do
    MemexProjectItemPrefiller.stub_const(:IN_CLAUSE_BATCH_SIZE, 3) do
      assert_query_count_per_table({
        pull_request_reviews: 2,
        pull_request_reviews_review_requests: 2,
      }) do
        project_items = @memex.memex_project_items.reject(&:archived?)
        prefill_result = MemexProjectItemPrefiller.new(
          project_items,
          columns: @memex.columns,
          read_denormalized_title: true,
          title_column: @memex.columns.find(&:title?)
        ).prefill

        # Call some methods that would result in database access if the prefiller didn't do its job.
        project_items.map do |i|
          i.to_hash(columns: @memex.columns, prefilled_associations: prefill_result)
        end
      end
    end
  end

  test "prefills issue and pull request content even more efficiently when reading denormalized data" do
    # Make sure that we actually attempt to serialize several columns.
    assert @memex.columns.length > 1

    total_query_count = assert_max_query_count_per_table({
      # We query `users` and `primary_avatars` once for the assignees column, once for reviewers
      # and once again for tracked_by_items ff.
      users: 3,
      primary_avatars: 2,
      # For most tables we expect just one query.
      assignments: 1,
      issues_labels: 1,
      labels: 1,
      issues: 1,
      issue_types: 1,
      repository_issue_types: 1,
      repositories: 1,
      memex_project_column_values: 1,
      close_issue_references: 1,
      issue_next_assignments: 1,
      review_requests: 1,
      pull_request_reviews: 1,
      pull_request_reviews_review_requests: 1,
      sub_issues: 1,
      sub_issue_lists: 1,

      # These are unrelated to this test, but help make sense of the assertion on total number of queries.
      memex_project_items: 1,
    }) do
      count_queries(ignore_feature_flags: true) do
        project_items = @memex.memex_project_items.reject(&:archived?)
        prefill_result = MemexProjectItemPrefiller.new(
          project_items,
          columns: @memex.columns,
          read_denormalized_title: true,
          title_column: @memex.columns.find(&:title?)
        ).prefill

        # Call some methods that would result in database access if the prefiller didn't do its job.
        project_items.map do |i|
          i.to_hash(
            columns: @memex.columns,
            prefilled_associations: prefill_result,
          )
        end
      end
    end

    # Finally, make sure this test explicitly accounts for all queries.
    assert_equal 20, total_query_count, "issued too many queries in total"
  end

  test "prefills archived items efficently" do
    memex = create(:memex_project, owner: @org)

    # Make sure that we actually attempt to serialize several columns.
    assert memex.columns.length > 1

    total_query_count = assert_max_query_count_per_table({
      # We query `users` and `primary_avatars` once for the assignees column and again for reviewers.
      # If there are archived items, we also query `users` and `primary_avatars` once to get all the archivers.
      # 1 of these users is the project owner, looked up for a feature flag
      users: 4,
      primary_avatars: 3,
      # For most tables we expect just one query.
      issues: 1,
      assignments: 1,
      issue_types: 1,
      issues_labels: 1,
      labels: 1,
      milestones: 1,
      repositories: 1,
      repository_issue_types: 1,
      memex_project_column_values: 1,
      close_issue_references: 1,
      issue_next_assignments: 1,
      review_requests: 1,
      pull_request_reviews: 1,
      pull_request_reviews_review_requests: 1,
      sub_issues: 1,
      sub_issue_lists: 1,

      # These are unrelated to this test, but help make sense of the assertion on total number of queries.
      memex_project_items: 1,
    }) do
      count_queries(ignore_feature_flags: true) do
        all_project_items_including_archived = @memex.memex_project_items
        prefill_result = MemexProjectItemPrefiller.new(
          all_project_items_including_archived,
          columns: memex.columns,
          read_denormalized_title: true,
          title_column: memex.columns.find(&:title?)
        ).prefill

        # Call some methods that would result in database access if the prefiller didn't do its job.
        all_project_items_including_archived.map do |i|
          i.to_hash(
            columns: memex.columns,
            prefilled_associations: prefill_result,
          )
        end
      end
    end

    # Finally, make sure this test explicitly accounts for all queries.
    assert_equal 22, total_query_count, "issued too many queries in total"
  end

  test "populates draft assignees correctly in the result object" do
    memex = create(:memex_project, owner: @org)
    title_column = memex.columns.find(&:title?)
    draft_issue_items = 5.times.map do |n|
      draft_issue = create(:draft_issue)
      draft_issue.update!(assignees: @org_members[0...n])
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: draft_issue)
    end
    assert_equal [0, 1, 2, 3, 4], draft_issue_items.map { |i| i.content.assignees.length }

    prefill_result = MemexProjectItemPrefiller.new(
      draft_issue_items,
      columns: memex.columns.select(&:assignees?),
      read_denormalized_title: true,
      title_column: title_column
    ).prefill

    draft_issue_items.each_with_index do |item, index|
      assert_equal @org_members[0...index].sort_by(&:login), prefill_result.assignees(item)
    end
  end

  test "populates assignees correctly in the result object" do
    memex = create(:memex_project, owner: @org)
    title_column = memex.columns.find(&:title?)
    issue_items = 5.times.map do |n|
      issue = create(:issue, repository: @repo, user: @admin)
      issue.add_assignees(@org_members[0...n])
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end
    assert_equal [0, 1, 2, 3, 4], issue_items.map { |i| i.content.assignees.length }

    prefill_result = MemexProjectItemPrefiller.new(
      issue_items,
      columns: memex.columns.select(&:assignees?),
      read_denormalized_title: true,
      title_column: title_column
    ).prefill

    issue_items.each_with_index do |item, index|
      assert_equal @org_members[0...index].sort_by(&:login), prefill_result.assignees(item)
    end
  end

  test "ignores dangling references to assignees" do
    # Create new org and members so as not to affect test fixtures that rely
    # on the existence of particular members.
    org = create(:organization, admin: @admin)
    repo = create(:private_repository, owner: org)
    members = 5.times.map do
      u = create(:verified_user)
      create(:primary_avatar, owner: u, updater: u)
      org.add_member(u)
      u
    end

    memex = create(:memex_project, owner: org)
    title_column = memex.columns.find(&:title?)
    issue_items = 5.times.map do |n|
      issue = create(:issue, repository: repo, user: @admin)
      issue.add_assignees(members[0...n])
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end
    assert_equal [0, 1, 2, 3, 4], issue_items.map { |i| i.content.assignees.length }

    # Create some dangling references by removing a row in `users` without removing the
    # corresponding, `assignments` rows.
    User.find(members[1].id).delete

    prefill_result = MemexProjectItemPrefiller.new(
      issue_items,
      columns: memex.columns.select(&:assignees?),
      read_denormalized_title: true,
      title_column: title_column
    ).prefill

    assert_empty prefill_result.assignees(issue_items[0])
    assert_equal [members[0]], prefill_result.assignees(issue_items[1])
    assert_equal [members[0]], prefill_result.assignees(issue_items[2])
    assert_equal [members[0], members[2]].sort_by(&:login), prefill_result.assignees(issue_items[3])
    assert_equal ([members[0]] + T.must(members[2...4])).sort_by(&:login), prefill_result.assignees(issue_items[4])
  end

  test "populates labels correctly in the result object" do
    memex = create(:memex_project, owner: @org)
    title_column = memex.columns.find(&:title?)
    issue_items = 3.times.map do |n|
      issue = create(:issue, repository: @repo, user: @admin)
      issue.add_labels(@repo_labels[0...n])
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end
    assert_equal [0, 1, 2], issue_items.map { |i| i.content.labels.length }

    prefill_result = MemexProjectItemPrefiller.new(
      issue_items,
      columns: memex.columns.select(&:labels?),
      read_denormalized_title: true,
      title_column: title_column
    ).prefill

    issue_items.each_with_index do |item, index|
      assert_equal @repo_labels[0...index].sort_by(&:name), prefill_result.labels(item)
    end
  end

  test "ignores dangling references to labels" do
    # Create new repo and labels so as not to affect test fixtures that rely
    # on the existence of particular labels.
    repo = create(:private_repository, owner: @org)
    repo.update!(labels: [
      create(:label, name: "bug :bug:", repository: repo),
      create(:label, name: "enhancement :sparkles:", repository: repo),
    ])
    labels = repo.labels.all.to_a

    memex = create(:memex_project, owner: @org)
    title_column = memex.columns.find(&:title?)
    issue_items = 3.times.map do |n|
      issue = create(:issue, repository: repo, user: @admin)
      issue.add_labels(labels[0...n])
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end
    assert_equal [0, 1, 2], issue_items.map { |i| i.content.labels.length }

    # Create some dangling references by removing a row in `labels` without removing the
    # corresponding, `issues_labels` rows.
    Label.find(labels[1].id).delete

    prefill_result = MemexProjectItemPrefiller.new(
      issue_items,
      columns: memex.columns.select(&:labels?),
      read_denormalized_title: true,
      title_column: title_column
    ).prefill

    assert_empty prefill_result.labels(issue_items[0])
    assert_equal [labels[0]], prefill_result.labels(issue_items[1])
    assert_equal [labels[0]], prefill_result.labels(issue_items[2])
  end

  test "populates repositories correctly in the result object" do
    memex = create(:memex_project, owner: @org)
    title_column = memex.columns.find(&:title?)
    repositories = create_list(:repository, 3, owner: @org)
    issue_items = repositories.map do |repo|
      create(
        :memex_project_item,
        :with_denormalized_title,
        memex_project: memex,
        content: create(:issue, repository: repo, user: @admin)
      )
    end
    assert_equal repositories.map(&:id), issue_items.map(&:repository_id)

    repo_column = memex.find_column_by_name_or_id(MemexProjectColumn::REPOSITORY_COLUMN_NAME)

    prefill_result = MemexProjectItemPrefiller.new(
      issue_items,
      columns: memex.columns.select(&:repository?),
      read_denormalized_title: true,
      title_column: title_column
    ).prefill

    issue_items.each_with_index do |item, index|
      assert_equal repositories[index].id, prefill_result.repository(item)&.id
    end
  end

  test "populates milestones correctly in the result object" do
    memex = create(:memex_project, owner: @org)
    title_column = memex.columns.find(&:title?)
    issue_items = 3.times.map do |n|
      milestone = @milestones[n]
      issue = create(:issue, repository: @repo, user: @admin, milestone: milestone)
      create(:memex_project_item, :with_denormalized_title, :with_denormalized_milestone, memex_project: memex, content: issue)
    end
    assert_equal @milestones.map(&:id) + [nil], issue_items.map { |i| i.content.milestone&.id }

    prefill_result = MemexProjectItemPrefiller.new(
      issue_items,
      columns: memex.columns.select(&:milestone?),
      read_denormalized_title: true,
      title_column: title_column
    ).prefill

    assert_equal @milestones[0].memex_column_hash, prefill_result.milestone(issue_items[0])
    assert_equal @milestones[1].memex_column_hash, prefill_result.milestone(issue_items[1])
    assert_nil prefill_result.milestone(issue_items[2])
  end

  test "populates issue types correctly in the result object" do
    memex = create(:memex_project, owner: @org)
    title_column = memex.columns.find(&:title?)
    issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
    test_issue_type = create(:issue_type, owner: @org, name: "test")
    random_issue_type = create(:issue_type, owner: @org, name: "random")

    repository = create(:repository, owner: @org)

    test_issue = create(:issue, repository: repository, issue_type: test_issue_type)
    test_item = create(:memex_project_item, memex_project: memex, content: test_issue)
    random_issue = create(:issue, repository: repository, issue_type: random_issue_type)
    random_item = create(:memex_project_item, memex_project: memex, content: random_issue)
    issue_without_issue_type = create(:issue, repository: repository, issue_type: nil)
    item_without_issue_type = create(:memex_project_item, memex_project: memex, content: issue_without_issue_type)

    memex_items = [
      test_item,
      random_item,
      item_without_issue_type,
    ]

    prefill_result = MemexProjectItemPrefiller.new(
      memex_items,
      columns: [issue_type_column],
      read_denormalized_title: true,
      title_column: title_column,
    ).prefill

    assert_equal test_issue_type, prefill_result.issue_type(test_item)
    assert_equal random_issue_type, prefill_result.issue_type(random_item)
    assert_nil prefill_result.issue_type(item_without_issue_type)
  end

  test "populates parent issue correctly in the result object" do
    memex = create(:memex_project, owner: @org)
    title_column = memex.columns.find(&:title?)
    parent_issue_column = memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)

    issues1 = create_hierarchy! <<~HIERARCHY
    - parent
      - child
    HIERARCHY

    issues2 = create_hierarchy! <<~HIERARCHY
    - parent
      - child
    HIERARCHY

    child1 = issues1["child"]
    child1_item = create(:memex_project_item, memex_project: memex, content: child1)
    child2 = issues2["child"]
    child2_item = create(:memex_project_item, memex_project: memex, content: child2)
    issue_without_parent = create(:issue)
    without_parent_item = create(:memex_project_item, memex_project: memex, content: issue_without_parent)

    repository = create(:repository, owner: @org)


    memex_items = [
      child1_item,
      child2_item,
      without_parent_item
    ]

    prefill_result = MemexProjectItemPrefiller.new(
      memex_items,
      columns: [parent_issue_column],
      read_denormalized_title: true,
      title_column: title_column,
    ).prefill

    assert_equal issues1["parent"], prefill_result.parent_issue(child1_item)
    assert_equal issues2["parent"], prefill_result.parent_issue(child2_item)
    assert_nil prefill_result.parent_issue(without_parent_item)
  end

  test "populates sub issues progress correctly in the result object" do
    memex = create(:memex_project, owner: @org)
    title_column = memex.columns.find(&:title?)
    sub_issues_progress = memex.find_column_by_name_or_id(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME)

    issues = create_hierarchy! <<~HIERARCHY
    - parent
      - child1
      - child2
    HIERARCHY

    parent_item = create(:memex_project_item, memex_project: memex, content: issues["parent"])

    issues["parent"]&.recalculate_sub_issue_list!

    memex_items = [
      parent_item
    ]

    prefill_result = MemexProjectItemPrefiller.new(
      memex_items,
      columns: [sub_issues_progress],
      read_denormalized_title: true,
      title_column: title_column,
    ).prefill

    assert_equal issues["parent"]&.sub_issue_list, prefill_result.sub_issues_progress(parent_item)
  end

  test "when reading non-denormalized data, prefills linked pull requests efficiently" do
    memex = create(:memex_project, owner: @org)
    pull_requests = create_list(:pull_request, 3, :with_mergeable_head, :merged, repository: @repo, user: @admin)
    # Include linked pull requests from other repositories.
    pull_request2 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo2, user: @admin)
    issue_items = 3.times.map do |n|
      issue = create(:issue, repository: @repo, user: @admin)
      create(:close_issue_reference, issue: issue, pull_request: pull_requests[n])
      create(:close_issue_reference, issue: issue, pull_request: pull_request2)
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end

    query_result = {}
    assert_query_count_per_table({
      # Load all refenced pull_request_ids for the issue_items.
      close_issue_references: 1,
      # Load all pull_requests for the referenced pull_request_ids.
      pull_requests: 1,
      # Load all pull_request "issue" parent objects.
      issues: 1,
      # Load all pull request repositories. The Repository is required during serialization for the linked PR url.
      repositories: 1
    }) do
      MemexProjectItemPrefiller.new(
        issue_items,
        columns: memex.columns.select(&:linked_pull_requests?),
        read_denormalized_title: false
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      issue_items.map { |i| i.to_hash(columns: memex.columns.select(&:linked_pull_requests?)) }
    end
  end

  test "when reading denormalized data, populates linked pull requests correctly and efficiently in the result object" do
    memex = create(:memex_project, owner: @org)
    pull_requests = create_list(:pull_request, 3, :with_mergeable_head, :merged, repository: @repo, user: @admin)
    # Include linked pull requests from other repositories.
    pull_request2 = create(:pull_request, :with_mergeable_head, :merged, repository: @repo2, user: @admin)
    3.times.map do |n|
      issue = create(:issue, repository: @repo, user: @admin)
      create(:close_issue_reference, issue: issue, pull_request: pull_requests[n])
      create(:close_issue_reference, issue: issue, pull_request: pull_request2)
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end

    create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: pull_request2)

    query_result = T.let(nil, T.nilable(MemexProjectItem::PrefilledAssociations))
    assert_query_count_per_table({
      # Load all refenced pull_request_ids for the issue_items.
      close_issue_references: 1,
      # Load all pull_requests for the referenced pull_request_ids.
      pull_requests: 1,
      # Load all pull_request "issue" parent objects.
      issues: 1,
      # Load all pull request repositories efficiently along with the other item/column ActiveRecords in fill_memex_repositories.
      # The Repository is required during serialization for the linked PR url.
      repositories: 1
    }) do
      query_result = MemexProjectItemPrefiller.new(
        memex.memex_project_items,
        columns: memex.columns.select(&:linked_pull_requests?),
        read_denormalized_title: true,
        title_column: memex.columns.find(&:title?)
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      memex.memex_project_items.map { |i| i.to_hash(columns: memex.columns.select(&:linked_pull_requests?), prefilled_associations: query_result) }
    end
  end

  test "when reading non-denormalized data, prefills parent issues efficiently" do
    memex = create(:memex_project, owner: @org)
    issue_items = 5.times.map do
      # create a new repository for each parent to ensure we don't have an N+1
      parent_repo = create(:private_repository, owner: @org)
      issue = create(:issue, repository: @repo, user: @admin)
      parent = create(:issue, repository: parent_repo, user: @admin)
      parent.add_sub_issue!(issue, @admin.id)
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end

    # include a pull request to ensure that we don't attempt to prefill this information on PR items
    pull_request = create(:pull_request, :disable_disk_access, repository: @repo2, user: @admin)
    pull_request_item = create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: pull_request)

    query_result = {}
    assert_query_count_per_table({
      sub_issues: 1,
      issues: 1,
      repositories: 1,
      sub_issue_lists: 1,
    }) do
      MemexProjectItemPrefiller.new(
        issue_items + [pull_request_item],
        columns: memex.columns.select(&:parent_issue?),
        read_denormalized_title: false
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      issue_items.map { |i| i.to_hash(columns: memex.columns.select(&:parent_issue?)) }
    end
  end

  test "when reading non-denormalized data, prefills parent issues efficiently when parents are in the project" do
    memex = create(:memex_project, owner: @org)
    parent_repo = create(:private_repository, owner: @org)
    issue_items = 5.times.map do
      issue = create(:issue, repository: @repo, user: @admin)
      parent = create(:issue, repository: parent_repo, user: @admin)
      parent.add_sub_issue!(issue, @admin.id)
      [create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue),
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: parent)]
    end.flatten

    query_result = {}
    assert_query_count_per_table({
      sub_issues: 1,
      issues: 0,
      repositories: 0,
      sub_issue_lists: 1,
    }) do
      MemexProjectItemPrefiller.new(
        issue_items,
        columns: memex.columns.select(&:parent_issue?),
        read_denormalized_title: false
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      issue_items.map { |i| i.to_hash(columns: memex.columns.select(&:parent_issue?)) }
    end
  end

  test "when reading denormalized data, populates parent issues correctly and efficiently in the result object" do
    memex = create(:memex_project, owner: @org)
    pull_request = create(:pull_request, :disable_disk_access, repository: @repo2, user: @admin)
    create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: pull_request)
    issue_items = 5.times.map do
      parent_repo = create(:private_repository, owner: @org)
      issue = create(:issue, repository: @repo, user: @admin)
      parent = create(:issue, repository: parent_repo, user: @admin)
      parent.add_sub_issue!(issue, @admin.id)
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end

    query_result = T.let(nil, T.nilable(MemexProjectItem::PrefilledAssociations))
    assert_query_count_per_table({
      sub_issues: 1,
      # Once for global_relay_ids, once for parent issues
      issues: 2,
      repositories: 1,
      sub_issue_lists: 1,
    }) do
      query_result = MemexProjectItemPrefiller.new(
        memex.memex_project_items,
        columns: memex.columns.select(&:parent_issue?),
        read_denormalized_title: true,
        title_column: memex.columns.find(&:title?)
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      memex.memex_project_items.map { |i| i.to_hash(columns: memex.columns.select(&:parent_issue?), prefilled_associations: query_result) }
    end
  end

  test "when reading non-denormalized data, prefills sub issues progress efficiently" do
    memex = create(:memex_project, owner: @org)
    issue_items = 5.times.map do
      parent_repo = create(:private_repository, owner: @org)
      issue = create(:issue, repository: @repo, user: @admin)
      parent = create(:issue, repository: parent_repo, user: @admin)
      parent.add_sub_issue!(issue, @admin.id)
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end

    query_result = {}
    assert_query_count_per_table({
      sub_issue_lists: 1,
      issues: 0
    }) do
      MemexProjectItemPrefiller.new(
        issue_items,
        columns: memex.columns.select(&:sub_issues_progress?),
        read_denormalized_title: false
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      issue_items.map { |i| i.to_hash(columns: memex.columns.select(&:sub_issues_progress?)) }
    end
  end

  test "when reading denormalized data, populates sub issues progress correctly and efficiently in the result object" do
    memex = create(:memex_project, owner: @org)
    issue_items = 5.times.map do
      parent_repo = create(:private_repository, owner: @org)
      issue = create(:issue, repository: @repo, user: @admin)
      parent = create(:issue, repository: parent_repo, user: @admin)
      parent.add_sub_issue!(issue, @admin.id)
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end

    query_result = T.let(nil, T.nilable(MemexProjectItem::PrefilledAssociations))
    assert_query_count_per_table({
      sub_issue_lists: 1,
      issues: 0
    }) do
      query_result = MemexProjectItemPrefiller.new(
        memex.memex_project_items,
        columns: memex.columns.select(&:sub_issues_progress?),
        read_denormalized_title: true,
        title_column: memex.columns.find(&:title?)
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      memex.memex_project_items.map { |i| i.to_hash(columns: memex.columns.select(&:sub_issues_progress?), prefilled_associations: query_result) }
    end
  end

  test "when reading non-denormalized data, prefills sub issues progress efficiently for both parent issue and sub-issues progress columns" do
    memex = create(:memex_project, owner: @org)
    issue_items = 5.times.map do
      parent_repo = create(:private_repository, owner: @org)
      issue = create(:issue, repository: @repo, user: @admin)
      parent = create(:issue, repository: parent_repo, user: @admin)
      parent.add_sub_issue!(issue, @admin.id)
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end

    query_result = {}
    assert_query_count_per_table({
      # Once for parent issue column, once for sub-issues progress column
      sub_issue_lists: 2,
      # Once for parent issues
      issues: 1
    }) do
      MemexProjectItemPrefiller.new(
        issue_items,
        columns: memex.columns.select { |column| column.parent_issue? or column.sub_issues_progress? },
        read_denormalized_title: false
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      issue_items.map { |i| i.to_hash(columns: memex.columns.select { |column| column.parent_issue? or column.sub_issues_progress? }) }
    end
  end

  test "when reading non-denormalized data, prefills sub issues progress efficiently for both parent issue and sub-issues progress columns when parents are in the project" do
    memex = create(:memex_project, owner: @org)
    issue_items = 5.times.map do
      parent_repo = create(:private_repository, owner: @org)
      issue = create(:issue, repository: @repo, user: @admin)
      parent = create(:issue, repository: parent_repo, user: @admin)
      parent.add_sub_issue!(issue, @admin.id)
      [create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue),
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: parent)]
    end.flatten

    query_result = {}
    assert_query_count_per_table({
      # Once for parent issue column, once for sub-issues progress column
      sub_issue_lists: 1,
      issues: 0
    }) do
      MemexProjectItemPrefiller.new(
        issue_items,
        columns: memex.columns.select { |column| column.parent_issue? or column.sub_issues_progress? },
        read_denormalized_title: false
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      issue_items.map { |i| i.to_hash(columns: memex.columns.select { |column| column.parent_issue? or column.sub_issues_progress? }) }
    end
  end

  test "when reading denormalized data, populates sub issues progress correctly and efficiently in the result object for both parent issue and sub-issues progress columns" do
    memex = create(:memex_project, owner: @org)
    issue_items = 5.times.map do
      parent_repo = create(:private_repository, owner: @org)
      issue = create(:issue, repository: @repo, user: @admin)
      parent = create(:issue, repository: parent_repo, user: @admin)
      parent.add_sub_issue!(issue, @admin.id)
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: issue)
    end

    query_result = T.let(nil, T.nilable(MemexProjectItem::PrefilledAssociations))
    assert_query_count_per_table({
      # Once for parent issue column, once for sub-issues progress column
      sub_issue_lists: 2,
      # Once for global_relay_ids, once for parent issues
      issues: 2,
    }) do
      query_result = MemexProjectItemPrefiller.new(
        memex.memex_project_items,
        columns: memex.columns.select { |column| column.parent_issue? or column.sub_issues_progress? },
        read_denormalized_title: true,
        title_column: memex.columns.find(&:title?)
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      memex.memex_project_items.map { |i| i.to_hash(columns: memex.columns.select { |column| column.parent_issue? or column.sub_issues_progress? }, prefilled_associations: query_result) }
    end
  end

  test "when reading non-denormalized data, prefills reviewers efficiently" do
    memex = create(:memex_project, owner: @org)
    pull_requests = create_list(:pull_request, 3, :with_mergeable_head, :merged, repository: @repo, user: @admin)
    pull_request_items = 3.times.map do |n|
      pull_requests[n].request_review_from(actor: @admin, reviewers: [@org_members[n]])
      create(:pull_request_review, :approved, pull_request: pull_requests[n], user: @org_members[n])
      create(:memex_project_item, memex_project: memex, content: pull_requests[n])
    end

    # Load items from database for correct query count.
    pull_request_items = MemexProjectItem.find(pull_request_items.map(&:id))

    assert_query_count_per_table({
      users: 3, # the pr author, the reviewers, and the request reviewers
      primary_avatars: 1,
      review_requests: 1,
      pull_request_reviews: 1,
      pull_requests: 1,
    }) do
      MemexProjectItemPrefiller.new(
        pull_request_items,
        columns: memex.columns.select(&:reviewers?),
        read_denormalized_title: false
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      pull_request_items.map { |i| i.to_hash(columns: memex.columns.select(&:reviewers?)) }
    end
  end

  test "when reading denormalized data, prefills reviewers efficiently" do
    memex = create(:memex_project, owner: @org)
    pull_requests = create_list(:pull_request, 3, :with_mergeable_head, :merged, repository: @repo, user: @admin)
    pull_request_items = 3.times.map do |n|
      pull_requests[n].request_review_from(actor: @admin, reviewers: [@org_members[n]])
      create(:pull_request_review, :approved, pull_request: pull_requests[n], user: @org_members[n])
      create(:memex_project_item, :with_denormalized_title, memex_project: memex, content: pull_requests[n])
    end

    assert_query_count_per_table({
      users: 2,
      primary_avatars: 1,
      review_requests: 1,
      pull_request_reviews: 1,
      pull_requests: 1,
    }) do
      @query_result = MemexProjectItemPrefiller.new(
        pull_request_items,
        columns: memex.columns.select(&:reviewers?),
        read_denormalized_title: true,
        title_column: memex.columns.find(&:title?)
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      pull_request_items.map { |i| i.to_hash(columns: memex.columns.select(&:reviewers?), prefilled_associations: @query_result) }
    end
  end

  test "when reading non-denormalized data, prefills issue types efficiently" do
    memex = create(:memex_project, owner: @org)
    issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
    test_issue_type = create(:issue_type, owner: @org, name: "test")
    random_issue_type = create(:issue_type, owner: @org, name: "random")
    repository = create(:repository, owner: @org)
    memex_items = create_list(:issue, 3, repository: repository, issue_type: test_issue_type).map do |issue|
      create(:memex_project_item, memex_project: memex, content: issue)
    end
    memex_items += create_list(:issue, 3, repository: repository, issue_type: random_issue_type).map do |issue|
      create(:memex_project_item, memex_project: memex, content: issue)
    end

    assert_query_count_per_table({
      issue_types: 1,
      issues: 0,
    }) do
      MemexProjectItemPrefiller.new(
        memex_items,
        columns: [issue_type_column],
        read_denormalized_title: false
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      memex_items.map { |i| i.to_hash(columns: [issue_type_column]) }
    end
  end

  test "when reading denormalized data, prefills issue types efficiently" do
    memex = create(:memex_project, owner: @org)
    issue_type_column = memex.find_column_by_name_or_id(MemexProjectColumn::TYPE_COLUMN_NAME)
    test_issue_type = create(:issue_type, owner: @org, name: "test")
    random_issue_type = create(:issue_type, owner: @org, name: "random")
    repository = create(:repository, owner: @org)
    memex_items = create_list(:issue, 3, repository: repository, issue_type: test_issue_type).map do |issue|
      create(:memex_project_item, memex_project: memex, content: issue)
    end
    memex_items += create_list(:issue, 3, repository: repository, issue_type: random_issue_type).map do |issue|
      create(:memex_project_item, memex_project: memex, content: issue)
    end

    assert_query_count_per_table({
      issue_types: 1,
      issues: 1,
    }) do
      @query_result = MemexProjectItemPrefiller.new(
        memex_items,
        columns: [issue_type_column],
        read_denormalized_title: true,
        title_column: memex.columns.find(&:title?)
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      memex_items.map { |i| i.to_hash(columns: [issue_type_column], prefilled_associations: @query_result) }
    end
  end

  test "doesn't prefill issue/pr assignees unnecessarily" do
    non_avatar_columns = @default_columns.reject do |c|
      c.assignees? || c.reviewers?
    end

    assert_max_query_count_per_table({ assignments: 0, primary_avatars: 0 }) do
      project_items = @memex.memex_project_items.reject(&:archived?)
      MemexProjectItemPrefiller.new(
        project_items,
        columns: non_avatar_columns
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      project_items.map { |i| i.to_hash(columns: non_avatar_columns) }
    end
  end

  test "doesn't prefill issue/pr labels unnecessarily" do
    non_label_columns = @default_columns.find_all do |c|
      c.name != MemexProjectColumn::LABELS_COLUMN_NAME
    end

    assert_max_query_count_per_table({ labels: 0 }) do
      MemexProjectItemPrefiller.new(
        @memex.memex_project_items,
        columns: non_label_columns
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      @memex.memex_project_items.map { |i| i.to_hash(columns: non_label_columns) }
    end
  end

  test "doesn't prefill issue/pr milestones unnecessarily" do
    non_milestone_columns = @default_columns.find_all do |c|
      c.name != MemexProjectColumn::MILESTONE_COLUMN_NAME
    end

    assert_max_query_count_per_table({ milestones: 0 }) do
      MemexProjectItemPrefiller.new(
        @memex.memex_project_items,
        columns: non_milestone_columns
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      @memex.memex_project_items.map { |i| i.to_hash(columns: non_milestone_columns) }
    end
  end

  test "doesn't prefill issue types unnecessarily" do
    non_issue_type_columns = @default_columns.reject(&:issue_type?)

    assert_max_query_count_per_table({ issue_types: 0 }) do
      MemexProjectItemPrefiller.new(
        @memex.memex_project_items,
        columns: non_issue_type_columns
      ).prefill

      # Call some methods that would result in database access if the prefiller didn't do its job.
      @memex.memex_project_items.map { |i| i.to_hash(columns: non_issue_type_columns) }
    end
  end

  test "prefills name_html content on a label efficiently" do
    issue_item = @memex.memex_project_items.find { |i| i.content_type == "Issue" }

    # Make sure that we actually need to process and cache the HTML for one of the labels under test.
    refute EmojiHtmlStringRenderer::SAFE_STRING_REGEXP.match?(issue_item.content.labels.first.name)

    MemexProjectItemPrefiller.new(
      @memex.memex_project_items,
      columns: [MemexProjectColumn.default_column("Labels")]
    ).prefill

    # From this point forward we shouldn't even read from the cache.
    GitHub.cache.stubs(:get).raises(
      StandardError.new("should not have called GitHub.cache.get")
    ) do
      GitHub.cache.stubs(:get_multi).raises(
        StandardError.new("should not have called GitHub.cache.get_multi")
      ) do

        serialized_items = @memex
          .memex_project_items
          .select { |i| %w[Issue PullRequest].include?(i.content_type) }
          .map { |i| i.to_hash(columns: [MemexProjectColumn.default_column("Labels")]) }

        assert serialized_items.all? { |i| i[:memex_project_column_values][0][:value][0][:name_html] }
      end
    end
  end

  test "doesn't prefill milestone data when read_denormalized_milestone flag is set" do
    # Make sure that we actually attempt to serialize several columns.
    assert @memex.columns.length > 1

    milestone_column = @memex.columns.find(&:milestone?)
    assert milestone_column

    total_query_count = assert_max_query_count_per_table({
      # One for assignees, one for reviewers, one for tracked_by_items ff.
      users: 3,
      primary_avatars: 2,
      # For most tables we expect just one query.
      assignments: 1,
      issues: 1,
      issue_types: 1,
      issues_labels: 1,
      labels: 1,
      repositories: 1,
      memex_project_column_values: 1,
      close_issue_references: 1,
      issue_next_assignments: 1,
      review_requests: 1,
      repository_issue_types: 1,
      pull_request_reviews: 1,
      pull_request_reviews_review_requests: 1,
      sub_issues: 1,
      sub_issue_lists: 1,

      # These are unrelated to this test, but help make sense of the assertion on total number of queries.
      memex_project_items: 1,

      # We should not need to hit the milestones tables since we're reading denormalized milestones
      milestones: 0,
    }) do
      count_queries(ignore_feature_flags: true) do
        project_items = @memex.memex_project_items.reject(&:archived?)
        prefill_result = MemexProjectItemPrefiller.new(
          project_items,
          columns: @memex.columns,
          read_denormalized_title: true,
          title_column: @memex.columns.find(&:title?),
          read_denormalized_milestone: true
        ).prefill

        # Call some methods that would result in database access if the prefiller didn't do its job.
        project_items.map do |i|
          i.to_hash(
            columns: @default_columns,
            prefilled_associations: prefill_result
          )
        end
      end
    end

    # Finally, make sure this test explicitly accounts for all queries.
    assert_equal 20, total_query_count, "issued too many queries in total"
  end

  test "prefill completions without items" do
    GitHub.flipper[:tasklist_block].enable
    GitHub.flipper[:memex_table_without_limits].disable
    GitHub.flipper[:memex_project_without_limits_public_beta].disable

    memex = create(:memex_project, owner: @org)
    tracks_column = memex.columns.find(&:tracks?)
    assert tracks_column

    prefill_result = MemexProjectItemPrefiller.new(
      memex.memex_project_items,
      columns: memex.columns,
      read_denormalized_title: true,
      title_column: memex.columns.find(&:title?)).prefill

    assert prefill_result
  end

  test "prefill tracked by items correctly" do
    GitHub.flipper[:tasklist_block].enable
    GitHub.flipper[:memex_table_without_limits].disable
    GitHub.flipper[:memex_project_without_limits_public_beta].disable

    memex = create(:memex_project, owner: @org)
    tracked_by_items_column = memex.columns.find(&:tracked_by?)
    refute_nil tracked_by_items_column


    child_issue = create(:issue, repository: @repo, user: @admin)
    item = create(:memex_project_item, :with_denormalized_title,
      memex_project: memex,
      content: child_issue,
      creator: @admin
    )

    other_issue = create(:issue, repository: @repo, user: @admin)
    create(:memex_project_item, :with_denormalized_title,
      memex_project: memex,
      content: other_issue,
      creator: @admin
    )

    issues_graph_client = mock_issues_graph_client

    issues_graph_client.expects(:get_project_tracked_by_items)
      .returns(as_tracked_by_items_result([
        {
          key: { ownerId: @repo.owner_id, itemId: child_issue.id },
          trackedByItems: []
        }
      ]))

    prefill_result = MemexProjectItemPrefiller.new(
      memex.memex_project_items,
      columns: memex.columns,
      read_denormalized_title: true,
      title_column: memex.columns.find(&:title?)
    ).prefill

    refute_nil prefill_result.tracked_by_items(item)
  end

  test "prefill completions for a single item correctly" do
    GitHub.flipper[:tasklist_block].enable
    GitHub.flipper[:optimize_single_memex_hierarchy_prefill].enable
    GitHub.flipper[:issue_hierarchy_state].enable
    GitHub.flipper[:memex_table_without_limits].disable
    GitHub.flipper[:memex_project_without_limits_public_beta].disable

    completion = { completed: 4, total: 10, percent: 40 }
    tracking_parent = IssuesGraph::Proto::Issue.new(
      completion: IssuesGraph::Proto::Completion.new(**completion)
    )

    memex = create(:memex_project, owner: @org)
    tracks_column = memex.columns.find(&:tracks?)
    refute_nil tracks_column

    child_issue = create(:issue, repository: @repo, user: @admin)
    child_item = create(:memex_project_item, :with_denormalized_title,
      memex_project: memex,
      content: child_issue,
      creator: @admin
    )

    issues_graph_client = mock_issues_graph_client

    # once for eager return for completions
    issues_graph_client.expects(:get_issue)
      .with(has_entries(key: IssuesGraph::Proto::Key.new(
        ownerId: @repo.owner_id,
        itemId: child_issue.id
        ))
      ).once
      .returns(as_tracked_issue_result(tracking_issues: [], parent: tracking_parent))

    prefill_result = MemexProjectItemPrefiller.new(
      memex.memex_project_items,
      columns: memex.columns,
      read_denormalized_title: true,
      title_column: memex.columns.find(&:title?)
    ).prefill

    refute_nil prefill_result.completion(child_item)
  end

  test "prefill tracked by for a single item correctly" do
    GitHub.flipper[:optimize_single_memex_hierarchy_prefill].enable
    GitHub.flipper[:tasklist_block].enable
    GitHub.flipper[:issue_hierarchy_state].enable
    GitHub.flipper[:memex_table_without_limits].disable
    GitHub.flipper[:memex_project_without_limits_public_beta].disable

    memex = create(:memex_project, owner: @org)
    tracked_by_items_column = memex.columns.find(&:tracked_by?)
    refute_nil tracked_by_items_column

    parent_issue = create(:issue, repository: @repo, user: @admin)
    child_issue = create(:issue, repository: @repo, user: @admin)
    child_item = create(:memex_project_item, :with_denormalized_title,
      memex_project: memex,
      content: child_issue,
      creator: @admin
    )

    tracked_by_data = {
      key: { ownerId: @repo.owner_id, itemId: parent_issue.id, primaryKey: nil },
      title: parent_issue.title,
      url: parent_issue.url,
      state: parent_issue.state.to_s,
      repoName: @repo.name,
      repoId: @repo.id,
      userName: @admin.name,
      number: parent_issue.number,
      labels: [],
      assignees: [],
      stateReason: parent_issue.state_reason.to_s,
      completion: {
        key: { ownerId: @repo.owner_id, itemId: parent_issue.id, primaryKey: nil },
        completed: 4, total: 10, percent: 40
      },
      position: 0
    }

    issues_graph_client = mock_issues_graph_client

    # eager return for tracked when the prefill only has one item
    issues_graph_client.expects(:get_issue)
      .with(has_entries(key: IssuesGraph::Proto::Key.new(
        ownerId: @repo.owner_id,
        itemId: child_issue.id
        ))
      ).once
      .returns(as_tracked_issue_result(tracked_by_issues: [tracked_by_data]))

    prefill_result = MemexProjectItemPrefiller.new(
      memex.memex_project_items,
      columns: memex.columns,
      read_denormalized_title: true,
      title_column: memex.columns.find(&:title?)
    ).prefill

    refute_nil prefill_result.tracked_by_items(child_item)
  end

  test "traces the prefill method" do
    # Make sure that we actually attempt to serialize several columns.
    assert @memex.columns.length > 1

    MemexProjectItemPrefiller.new(@memex.memex_project_items, columns: @memex.columns).prefill

    refute_nil span = find_span_by(name: "memex_project_item_prefiller#prefill")

    complex_attributes = %w[gh.memex.prefiller.field_count.status gh.memex.prefiller.height_bucket gh.memex.prefiller.width_bucket]
    complex_attributes += MemexProjectColumn.data_types.keys.map { |data_type| "gh.memex.prefiller.field_count.#{data_type}" }

    # Verify simple attributes exactly.
    assert_same_hash(
      {
        "gh.memex.project_id" => @memex.id,
        "gh.memex.prefiller.height" => @memex.memex_project_items.length,
        "gh.memex.prefiller.width" => @memex.columns.length,
        "gh.memex.prefiller.read_denormalized_title" => false,
        "gh.memex.prefiller.read_denormalized_milestone" => true,
        "gh.memex.prefiller.add_item_id_clause_to_column_values_query" => false,
      },
      span.attributes.except(*complex_attributes)
    )

    # Verify that more complex attributes are at least non-nil
    complex_attributes.each do |attribute|
      refute_nil span.attributes[attribute], "expected '#{attribute}' span attribute to be non-nil"
    end
  end

  test "handles non-existent reviewers gracefully" do
    team = create(:team, organization: @org, name: "Employee", privacy: :closed)
    source = create(:repository, owner: @org)
    team.add_repository(source, :push)
    team.add_member @admin

    pull_request = create(
      :pull_request,
      :disable_disk_access,
      repository: source,
      head_user: @admin
    )

    create(:review_request, pull_request: pull_request, reviewer: team)
    item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: pull_request)

    assert_equal 1, pull_request.review_requests.size

    team.destroy!
    pull_request.reload
    item.reload

    assert_equal 1, pull_request.review_requests.size

    assert_nothing_raised do
      @query_result = MemexProjectItemPrefiller.new(
        [item],
        columns: @memex.columns.select(&:reviewers?),
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill
      assert @query_result
    end
  end

  test "queries column values only by column ID by default" do
    # Make sure that we have a column that requires a query against `memex_project_column_values`
    refute_nil @memex.columns.find(&:generic_type?)

    _, queries = log_queries do
      MemexProjectItemPrefiller.new(@memex.memex_project_items, columns: @memex.columns).prefill
    end

    legacy_column_values_query = queries.find do |q|
      table = "memex_project_column_values"
      q.digested_sql == "SELECT #{table}.* FROM #{table} WHERE #{table}.memex_project_column_id IN ?"
    end

    refute_nil  legacy_column_values_query
  end

  test "adds an item ID clause to the query that retrieves column values when instructed to" do
    # Make sure that we have a column that requires a query against `memex_project_column_values`
    refute_nil @memex.columns.find(&:generic_type?)

    _, queries = log_queries do
      MemexProjectItemPrefiller
        .new(
          @memex.memex_project_items,
          columns: @memex.columns,
          add_item_id_clause_to_column_values_query: true
        )
        .prefill
    end

    optimized_column_values_query = queries.find do |q|
      table = "memex_project_column_values"
      q.digested_sql == (
        "SELECT #{table}.* FROM #{table} WHERE #{table}.memex_project_column_id IN ? " +
        "AND #{table}.memex_project_item_id IN ?"
      )
    end

    refute_nil optimized_column_values_query
  end
end
