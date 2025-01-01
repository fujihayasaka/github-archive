# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesMemexProjectItemQueryTest < GitHub::TestCase
  include MemexHelpers
  include DogstatsTestHelpers
  include HydroTestHelpers
  include ProjectsProcessorTestHelpers
  include SubIssuesHelpers

  MISSING_VALUE_GROUP_KEY = MemexProjectColumn::Groupable::MISSING_VALUE_GROUP_KEY

  fixtures do
    @user = create(:verified_user, login: "project-admin")
    @memex = create(:memex_project, owner: @user)
    @repo = create(:repository, owner: @user, name: "app")
    @label_bug = create(:label, name: "bug", repository: @repo)
    @label_epic = create(:label, name: "epic", repository: @repo)

    @unarchived_items = 5.times.map do |n|
      issue = create(:issue, title: "Unarchived issue #{n}", repository: @repo)
      create(:memex_project_item, priority: n + 1, priority_numerator: 2 * n + 1, priority_denominator: 2, archived_at: nil, memex_project: @memex, content: issue)
    end
    @archived_items = 5.times.map do |n|
      issue = create(:issue, title: "Archived issue #{n}", repository: @repo)
      archived_at = Time.zone.now - n * 5.minutes # Space out archived times so that they are not accidentally equal
      create(:memex_project_item, :archived, archived_at: archived_at, memex_project: @memex, content: issue)
    end
    @unrelated_archived_items = create_list(:memex_project_item, 5, :archived) # These default to issue items with randomly generated repositories
    @all_items = @unarchived_items + @archived_items + @unrelated_archived_items
  end

  setup do
    setup_search
  end

  teardown_once do
    teardown_search
  end

  context "#execute" do
    test "returns an empty response when Elasticsearch raises an error" do
      Elastomer::Indexes::MemexProjectItems.any_instance.stubs(:search).raises(ElastomerClient::Client::RequestError.new)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
      ).execute
      assert response.error_details.present?
      assert response.models.empty?
    end

    test "returns an empty grouped response when Elasticsearch raises an error" do
      Elastomer::Indexes::MemexProjectItems.any_instance.stubs(:search).raises(ElastomerClient::Client::RequestError.new)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: @memex.status_column.id,
          include_empty_groups: false
        ),
      ).execute
      assert response.grouped?
      assert response.error_details.present?
      assert response.models.empty?
    end

    test "returns correct results for a query that requests only archived items" do
      populate_elasticsearch_index!(@all_items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
      ).execute

      assert_same_elements response.results.map { |r| r["_id"].to_i }, @archived_items.map(&:id)
    end

    test "returns correct results for a query that requests only unarchived items" do
      populate_elasticsearch_index!(@all_items)
      response = Search::Queries::MemexProjectItemQuery.new(project: @memex, viewer: @user).execute
      assert_same_elements response.results.map { |r| r["_id"].to_i }, @unarchived_items.map(&:id)
    end

    test "paginates results based on additional sort parameter passed into the query (archived_at)" do
      populate_elasticsearch_index!(@all_items)

      # Sort by item.archived_at desc which we pass in as the sort parameter in the query
      expected_sorted_item_ids = @archived_items
        .sort_by(&:archived_at)
        .reverse
        .map(&:id)

      sort = [{ archived_at: "desc" }]

      first_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        first: 3,
        sort: sort,
      ).execute

      assert_equal expected_sorted_item_ids.slice(0, 3), first_page.results.map { |r| r["_id"].to_i }
      assert first_page.has_next_page

      next_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        first: 3,
        after: first_page.end_cursor,
        sort: sort,
      ).execute
      assert_equal expected_sorted_item_ids.slice(3, 3), next_page.results.map { |r| r["_id"].to_i }
      refute next_page.has_next_page
      assert next_page.has_previous_page

      previous_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        last: 3,
        before: next_page.start_cursor,
        sort: sort,
      ).execute
      assert_equal expected_sorted_item_ids.slice(0, 3), previous_page.results.map { |r| r["_id"].to_i }
    end

    test "paginates results based on priority sort value" do
      populate_elasticsearch_index!(@all_items)

      expected_sorted_item_ids = @unarchived_items
        .sort_by { |i| -i.virtual_priority }
        .map(&:id)
      assert expected_sorted_item_ids.length > 4

      first_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        first: 3
      ).execute
      assert_same_elements first_page.results.map { |r| r["_id"].to_i }, expected_sorted_item_ids.slice(0, 3)
      assert first_page.has_next_page

      next_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        first: 3,
        after: first_page.end_cursor,
      ).execute
      assert_same_elements next_page.results.map { |r| r["_id"].to_i }, expected_sorted_item_ids.slice(3, 3)
      refute next_page.has_next_page
    end

    test "returns correct paginated results when sorting a query, including sorting by a secondary field" do
      # get/create columns to sort on
      @assignees_column = @memex.find_column_by_name_or_id(MemexProjectColumn::ASSIGNEES_COLUMN_NAME)
      @status_column = @memex.status_column
      @custom_single_select_column = @memex.add_user_defined_column(
        name: name,
        data_type: "single_select",
        position: @memex.columns.count + 1,
        creator: @user,
        settings: {
          "options" => [
            { id: "11111111", name: "first", color: "GREEN", description: "first" },
            { id: "22222222", name: "second", color: "YELLOW", description: "second" },
          ]
        }
      )

      @status_options = @status_column.settings["options"]
      @custom_single_select_options = @custom_single_select_column.settings["options"]


      @unarchived_items.each_with_index do |item, index|
        target_status_option = @status_options[index % @status_options.length]
        # set second single select column value to test secondary sorting
        target_custom_single_select_option = @custom_single_select_options[index % @custom_single_select_options.length]

        item.set_column_value(@status_column, target_status_option["id"], @user)
        item.set_column_value(@custom_single_select_column, target_custom_single_select_option["id"], @user)
      end

      populate_elasticsearch_index!(@all_items)

      sort = [@status_column.to_field.sort_fragment(direction: "desc"), @custom_single_select_column.to_field.sort_fragment(direction: "desc")]

      first_page = Search::Queries::MemexProjectItemQuery
      .new(
        project: @memex.reload,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Unarchived,
        first: 3,
        sort: sort,
      )
      .execute

      # Expect items to be sorted by the custom_single_select_options array order, then by the status_options array order
      expected_sorted_item_ids = @unarchived_items
        .sort_by { |i| @custom_single_select_options.index { |o| o["name"] == i.column_value(@custom_single_select_column, require_prefilled_associations: false) } }
        .sort_by { |i| @status_options.index { |o| o["name"] == i.column_value(@status_column, require_prefilled_associations: false) } }
        .reverse
        .map(&:id)

      assert_equal expected_sorted_item_ids.slice(0, 3), first_page.results.map { |r| r["_id"].to_i }
      assert first_page.has_next_page

      next_page = Search::Queries::MemexProjectItemQuery
      .new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Unarchived,
        first: 3,
        sort: sort,
        after: first_page.end_cursor,
      )
      .execute

      assert_same_elements next_page.results.map { |r| r["_id"].to_i }, expected_sorted_item_ids.slice(3, 3)
      refute next_page.has_next_page
    end

    test "retrieves previous page of results based on :before cursor" do
      populate_elasticsearch_index!(@all_items)

      first_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        first: 3,
      ).execute
      refute first_page.has_previous_page
      assert first_page.has_next_page

      next_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        first: 3,
        after: first_page.end_cursor,
      ).execute
      refute next_page.has_next_page
      assert next_page.has_previous_page

      previous_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        last: 3,
        before: next_page.start_cursor,
      ).execute
      assert_equal previous_page.results, first_page.results
      assert_equal previous_page.start_cursor, first_page.start_cursor
      assert_equal previous_page.end_cursor, first_page.end_cursor
      assert previous_page.has_next_page
      refute previous_page.has_previous_page
    end

    test "sorts results by id if priority is nil" do
      populate_elasticsearch_index!(@all_items)

      assert_empty @archived_items
        .map { |i| i.priority }
        .compact

      first_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        first: 3,
      ).execute

      expected_ids = @archived_items.sort_by! { |i| [i.id] }.map(&:id)
      assert expected_ids.length > 3
      assert_equal expected_ids.slice(0, 3), first_page.results.map { |r| r["_id"].to_i }

      next_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        first: 3,
        after: first_page.end_cursor,
      ).execute
      assert_equal expected_ids.slice(3, 3), next_page.results.map { |r| r["_id"].to_i }

      previous_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        last: 3,
        before: next_page.start_cursor,
      ).execute
      assert_equal expected_ids.slice(0, 3), previous_page.results.map { |r| r["_id"].to_i }
    end

    test "sorts results by the decimal virtual priority value in descending order by default" do
      items = [
        { priority_numerator: 1,  priority_denominator: 1 },  # => virtual_priority: 1
        { priority_numerator: 2,  priority_denominator: 1 },  # => virtual_priority: 2
        { priority_numerator: 10, priority_denominator: 1 },  # => virtual_priority: 10
        { priority_numerator: 1,  priority_denominator: 10 }  # => virtual_priority: 0.1
      ]
      .map { |rational_priority| create(:memex_project_item, memex_project: @memex, **rational_priority) }
      .map(&:reload) # Must reload the items in order to populate the `virtual_priority` field

      item_ids_in_priority_desc_order = [
        items[2].id,
        items[1].id,
        items[0].id,
        items[3].id
      ]

      populate_elasticsearch_index!(items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
      ).execute
      response_item_ids = response.results.map { |r| r["_id"].to_i }

      assert_equal item_ids_in_priority_desc_order, response_item_ids
    end

    test "sorts results by the decimal virtual priority value in descending order when `graphql_reverse_priority` is falsy" do
      items = [
        { priority_numerator: 1,  priority_denominator: 1 },  # => virtual_priority: 1
        { priority_numerator: 2,  priority_denominator: 1 },  # => virtual_priority: 2
        { priority_numerator: 10, priority_denominator: 1 },  # => virtual_priority: 10
        { priority_numerator: 1,  priority_denominator: 10 }  # => virtual_priority: 0.1
      ]
      .map { |rational_priority| create(:memex_project_item, memex_project: @memex, **rational_priority) }
      .map(&:reload) # Must reload the items in order to populate the `virtual_priority` field

      item_ids_in_priority_desc_order = [
        items[2].id,
        items[1].id,
        items[0].id,
        items[3].id
      ]

      populate_elasticsearch_index!(items)

      response = Search::Queries::MemexProjectItemQuery.graphql_query(
        project: @memex,
        viewer: @user
      ).execute
      response_item_ids = response.results.map { |r| r["_id"].to_i }

      assert_equal item_ids_in_priority_desc_order, response_item_ids
    end

    test "sorts results by the decimal virtual priority value in ascending order when `graphql_reverse_priority` is truthy" do
      items = [
        { priority_numerator: 1,  priority_denominator: 1 },  # => virtual_priority: 1
        { priority_numerator: 2,  priority_denominator: 1 },  # => virtual_priority: 2
        { priority_numerator: 10, priority_denominator: 1 },  # => virtual_priority: 10
        { priority_numerator: 1,  priority_denominator: 10 }  # => virtual_priority: 0.1
      ]
      .map { |rational_priority| create(:memex_project_item, memex_project: @memex, **rational_priority) }
      .map(&:reload) # Must reload the items in order to populate the `virtual_priority` field

      item_ids_in_priority_asc_order = [
        items[3].id,
        items[0].id,
        items[1].id,
        items[2].id
      ]

      populate_elasticsearch_index!(items)

      response = Search::Queries::MemexProjectItemQuery.graphql_query(
        project: @memex,
        viewer: @user,
        reverse_priority: true
      ).execute
      response_item_ids = response.results.map { |r| r["_id"].to_i }

      assert_equal item_ids_in_priority_asc_order, response_item_ids
    end

    test "sorts results by id when ElasticSearch sort loses precision converting unsigned long priorities to float or long" do
      # ElasticSearch does not support sorting on unsigned longs (the big_int datatype of the item priority attribute).
      # Signficant figures are lost when converted to a float or long, causing priorities between items to appear equal.
      # See https://github.com/github/projects-platform/issues/999#issuecomment-1751311289 for more information

      prioritized_items = [
        create(:memex_project_item, memex_project: @memex, priority: MemexProjectView::MAX_BIGINT_VALUE / 2 + 10),
        create(:memex_project_item, memex_project: @memex, priority: MemexProjectView::MAX_BIGINT_VALUE / 2 - 10),
        create(:memex_project_item, memex_project: @memex, priority: MemexProjectView::MAX_BIGINT_VALUE / 2 + 5),
        create(:memex_project_item, memex_project: @memex, priority: MemexProjectView::MAX_BIGINT_VALUE / 2 - 5),
      ]

      item_ids_in_id_asc_order = prioritized_items.map(&:id)
      item_ids_in_priority_desc_order = [prioritized_items[0].id, prioritized_items[2].id, prioritized_items[3].id, prioritized_items[1].id]

      populate_elasticsearch_index!(prioritized_items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
      ).execute

      response_item_ids = response.results.map { |r| r["_id"].to_i }

      refute_equal item_ids_in_priority_desc_order, response_item_ids
      assert_equal item_ids_in_id_asc_order, response_item_ids
    end

    test "appends items missing the sort field to the end of the results" do
      populate_elasticsearch_index!(@all_items)

      assert_empty @archived_items.map(&:priority).compact
      assert_empty @unarchived_items.map(&:archived_at).compact
      assert_equal @unarchived_items.map(&:priority).uniq.length, @unarchived_items.length

      expected_sorted_item_ids = (
        @archived_items.sort_by { |item| -item.archived_at.to_i } +
        @unarchived_items.sort_by { |item| -item.priority }
      ).map(&:id)

      first_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::All,
        first: 8,
        sort: [{ archived_at: "desc" }],
      ).execute

      assert_equal expected_sorted_item_ids.slice(0, 8), first_page.results.map { |r| r["_id"].to_i }

      next_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::All,
        first: 8,
        after: first_page.end_cursor,
        sort: [{ archived_at: "desc" }],
      ).execute

      assert_equal expected_sorted_item_ids.slice(8, 2), next_page.results.map { |r| r["_id"].to_i }

      previous_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::All,
        last: 8,
        before: next_page.start_cursor,
        sort: [{ archived_at: "desc" }],
      ).execute

      # Paging back maintains correct sort order
      assert_equal first_page.results, previous_page.results
    end

    test "appends items missing the sort field to the end of the results with `virtual_priority`" do
      populate_elasticsearch_index!(@all_items)

      assert_empty @archived_items.map(&:virtual_priority).compact
      assert_empty @unarchived_items.map(&:archived_at).compact
      assert_equal @unarchived_items.map(&:virtual_priority).uniq.length, @unarchived_items.length

      expected_sorted_item_ids = (
        @archived_items.sort_by { |item| -item.archived_at.to_i } +
        @unarchived_items.sort_by { |item| -item.virtual_priority }
      ).map(&:id)

      first_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::All,
        first: 8,
        sort: [{ archived_at: "desc" }],
      ).execute

      assert_equal expected_sorted_item_ids.slice(0, 8), first_page.results.map { |r| r["_id"].to_i }

      next_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::All,
        first: 8,
        after: first_page.end_cursor,
        sort: [{ archived_at: "desc" }],
      ).execute

      assert_equal expected_sorted_item_ids.slice(8, 2), next_page.results.map { |r| r["_id"].to_i }

      previous_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::All,
        last: 8,
        before: next_page.start_cursor,
        sort: [{ archived_at: "desc" }],
      ).execute

      # Paging back maintains correct sort order
      assert_equal first_page.results, previous_page.results
    end

    test "per_page of response matches original page size param" do
      per_page = 5
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        first: per_page,
      )
      assert_equal query.per_page, per_page + 1
      response = query.execute
      assert_equal response.per_page, per_page
    end

    test "returns correct results for a query that filters by assignee", es_8_only: true do
      repo = create(:repository, owner: @user)
      assignees_field = @memex.columns.find(&:assignees?).to_field

      assigned_issue = create(:issue, assignee: @user, repository: repo)
      assigned_item = create(:memex_project_item, content: assigned_issue, memex_project: @memex)

      someone_else = create(:verified_user, login: "someone-else")
      repo.add_member(someone_else)
      issue_assigned_to_someone_else = create(:issue, assignee: someone_else, repository: repo)
      item_assigned_to_someone_else = create(:memex_project_item, content: issue_assigned_to_someone_else, memex_project: @memex)

      populate_elasticsearch_index!([assigned_item, item_assigned_to_someone_else])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "assignee:#{@user}",
        source_fields: true,
      ).execute

      assert_equal 1, response.total
      assert_equal @user.login, field_value(assignees_field, response.results.first).dig(0, "login")
    end

    test "returns correct results for a query that filters by a combination of assignees and labels", es_8_only: true do
      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "stimpy")
      @repo.add_member(user_ren)
      @repo.add_member(user_stimpy)

      items = Array[create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)] # 0
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) # 1
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo, labels: [@label_bug]), memex_project: @memex) # 2
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo, labels: [@label_epic]), memex_project: @memex) # 3
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @repo, labels: [@label_bug]), memex_project: @memex) # 4
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @repo, labels: [@label_bug, @label_epic]), memex_project: @memex) # 5
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @repo, labels: [@label_epic]), memex_project: @memex) # 6

      populate_elasticsearch_index!(items)

      # 1) Search for ren's items (assignee).
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "assignee:#{user_ren.login}",
        source_fields: true,
      ).execute

      expected_matching_ids = [1, 2, 3, 5, 6].map { |i| items[i].id }
      assert_same_elements expected_matching_ids, response.results.map { |i| i.dig("_id").to_i }

      # 2) Search for ren's bug items (assignee AND label).
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "assignee:#{user_ren.login}" + " label:bug",
        source_fields: true,
      ).execute

      expected_matching_ids = [2, 5].map { |i| items[i].id }
      assert_same_elements expected_matching_ids, response.results.map { |i| i.dig("_id").to_i }

      # 3) Search for ren AND stimpy's bug items (assignee AND assignee AND label).
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "assignee:#{user_ren.login} label:bug assignee:#{user_stimpy.login}",
        source_fields: true,
      ).execute

      expected_matching_ids = [5].map { |i| items[i].id }
      assert_same_elements expected_matching_ids, response.results.map { |i| i.dig("_id").to_i }

      # 4) Search for ren OR stimpy's bug items (assignee OR assignee AND label).
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "assignee:#{user_ren.login},#{user_stimpy.login} label:bug",
        source_fields: true,
      ).execute

      expected_matching_ids = [2, 4, 5].map { |i| items[i].id }
      assert_same_elements expected_matching_ids, response.results.map { |i| i.dig("_id").to_i }

      # 5) Search for ren's items with no labels (assignee AND no label).
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "assignee:#{user_ren.login} no:label",
        source_fields: true,
      ).execute

      expected_matching_ids = [1].map { |i| items[i].id }
      assert_same_elements expected_matching_ids, response.results.map { |i| i.dig("_id").to_i }
    end

    test "returns correct results for a query that filters by '-no:assignee'" do
      assignees_field = @memex.columns.find(&:assignees?).to_field

      items = [
        assigned_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, assignee: @user, repository: @repo)),
        unassigned_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, repository: @repo)),
      ]

      populate_elasticsearch_index!([assigned_item, unassigned_item])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "-no:assignee",
        source_fields: true,
      ).execute

      assert_equal [assigned_item.id], response.results.map { |r| r["_id"].to_i }
    end

    test "returns correct results for a query that filters by '-no:assignee,label' (item has EITHER an assignee or a label)" do
      assignees_field = @memex.columns.find(&:assignees?).to_field
      labels_field = @memex.columns.find(&:labels?).to_field

      items = [
        assigned_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, repository: @repo, assignees: [@user])),
        labeled_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, repository: @repo, labels: [@label_bug])),
        assigned_and_labeled_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, repository: @repo, assignees: [@user], labels: [@label_bug])),
        neither_assigned_nor_labeled_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, repository: @repo)),
      ]

      populate_elasticsearch_index!(items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "-no:assignee,label",
        source_fields: true,
      ).execute

      assert_same_elements(
        [assigned_item, labeled_item, assigned_and_labeled_item].map(&:id),
        response.results.map { |r| r["_id"].to_i }
      )
    end

    test "returns correct results for a query that filters by '-no:assignee -no:label' (item has BOTH an assignee AND a label)" do
      assignees_field = @memex.columns.find(&:assignees?).to_field
      labels_field = @memex.columns.find(&:labels?).to_field

      items = [
        assigned_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, repository: @repo, assignees: [@user])),
        labeled_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, repository: @repo, labels: [@label_bug])),
        assigned_and_labeled_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, repository: @repo, assignees: [@user], labels: [@label_bug])),
        neither_assigned_nor_labeled_item = create(:memex_project_item, memex_project: @memex, content: create(:issue, repository: @repo)),
      ]

      populate_elasticsearch_index!(items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "-no:assignee -no:label",
        source_fields: true,
      ).execute

      assert_same_elements [assigned_and_labeled_item.id], response.results.map { |r| r["_id"].to_i }
    end

    test "returns correct results for a query that filters by text column value", es_8_only: true do
      repo = create(:repository, owner: @user)
      issue = create(:issue, assignee: @user, repository: repo)
      issue_2 = create(:issue, assignee: @user, repository: repo)
      item = create(:memex_project_item, content: issue, memex_project: @memex)
      item_2 = create(:memex_project_item, content: issue_2, memex_project: @memex)

      text_column = create(:memex_project_column, data_type: :text, name: "My Text Column", memex_project: @memex)
      create(:text_memex_project_column_value,
        memex_project_item: item,
        column: text_column,
        value: "Find, me"
      )
      create(:text_memex_project_column_value,
        memex_project_item: item_2,
        column: text_column,
        value: "A very different value"
      )

      populate_elasticsearch_index!([item, item_2])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: 'my-text-column:"Find, me"',
        source_fields: true,
      ).execute

      assert_equal 1, response.total
      assert_equal "Find, me", field_value(text_column.to_field, response.results.first)
    end

    test "returns correct results for an OR query on text column value", es_8_only: true do
      repo = create(:repository, owner: @user)
      issue = create(:issue, assignee: @user, repository: repo)
      issue_2 = create(:issue, assignee: @user, repository: repo)
      issue_3 = create(:issue, assignee: @user, repository: repo)
      item = create(:memex_project_item, content: issue, memex_project: @memex)
      item_2 = create(:memex_project_item, content: issue_2, memex_project: @memex)
      item_3 = create(:memex_project_item, content: issue_3, memex_project: @memex)

      text_column = create(:memex_project_column, data_type: :text, name: "Blocked Reason", memex_project: @memex)
      create(:text_memex_project_column_value,
        memex_project_item: item,
        column: text_column,
        value: "deploy freeze"
      )
      create(:text_memex_project_column_value,
        memex_project_item: item_2,
        column: text_column,
        value: "Waiting for feedback from Product"
      )
      create(:text_memex_project_column_value,
        memex_project_item: item_3,
        column: text_column,
        value: "Something different"
      )

      populate_elasticsearch_index!([item, item_2, item_3])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: 'blocked-reason:"deploy freeze","Waiting for feedback from Product"',
        source_fields: true,
      ).execute

      assert_equal 2, response.total
      found_values = [field_value(text_column.to_field, response.results.first), field_value(text_column.to_field, response.results.second)]
      assert_includes found_values, "deploy freeze"
      assert_includes found_values, "Waiting for feedback from Product"
    end

    test "returns correct results for a query that filters by single-select value", es_8_only: true do
      repo = create(:repository, owner: @user)
      issue = create(:issue, assignee: @user, repository: repo)
      issue_2 = create(:issue, assignee: @user, repository: repo)
      item = create(:memex_project_item, content: issue, memex_project: @memex)
      item_2 = create(:memex_project_item, content: issue_2, memex_project: @memex)
      single_select_column = create(
        :single_select_memex_column,
        memex_project: @memex,
        settings: {
          "options" => [
            { id: "aaaaaaaa", name: "smaller", name_html: "smaller", color: "RED", description: "", description_html: "" },
            { id: "bbbbbbbb", name: "small", name_html: "small", color: "YELLOW", description: "", description_html: "" },
            { id: "cccccccc", name: "medium", name_html: "medium", color: "ORANGE", description: "", description_html: "" },
            { id: "dddddddd", name: "large", name_html: "large", color: "BLUE", description: "", description_html: "" },
            { id: "ffffffff", name: "xlarge", name_html: "xlarge", color: "GREEN", description: "should probably be broken down", description_html: "should probably be broken down" },
          ]
        })
      create(
        :single_select_memex_project_column_value,
        value: single_select_column.settings["options"][1]["id"],
        memex_project_column: single_select_column,
        memex_project_item: item
      )
      # this item shouldn't come back in the response
      create(
        :single_select_memex_project_column_value,
        value: single_select_column.settings["options"][0]["id"],
        memex_project_column: single_select_column,
        memex_project_item: item_2
      )

      populate_elasticsearch_index!([item, item_2])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "estimate:small",
        source_fields: true,
      ).execute

      assert_equal 1, response.total
      assert_equal({ id: "bbbbbbbb", name: "small" }.stringify_keys, field_value(single_select_column.to_field, response.results.first))
    end

    test "returns correct results for a query that filters on a field with an emoji in the name", es_8_only: true do
      severity_column = create(
        :single_select_memex_column,
        name: "Severity 💣 🔥",
        memex_project: @memex,
        settings: {
          "options" => [
            { id: "aaaaaaaa", name: "Really Really Bad" },
            { id: "bbbbbbbb", name: "Really Bad" },
            { id: "cccccccc", name: "Not So Bad" },
            { id: "dddddddd", name: "Meh" },
          ]
        })

      items = create_list(:memex_project_item, 5, memex_project: @memex)
      items[0].set_column_value(severity_column, "aaaaaaaa", @user)
      items[1].set_column_value(severity_column, "bbbbbbbb", @user)
      items[2].set_column_value(severity_column, "cccccccc", @user)
      items[3].set_column_value(severity_column, "bbbbbbbb", @user)

      populate_elasticsearch_index!(items)

      # 1) search for "Really Bad" items.
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "severity-💣-🔥:\"Really Bad\"",
        source_fields: true,
      ).execute

      expected_matching_ids = [items[1].id, items[3].id]
      assert_same_elements expected_matching_ids, response.results.map { |i| i.dig("_id").to_i }

      # 2) search for the negative of "Really Bad" items (i.e., everything except "Really Bad" items).
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "-severity-💣-🔥:\"Really Bad\"",
        source_fields: true,
      ).execute

      expected_matching_ids = [items[0].id, items[2].id, items[4].id]
      assert_same_elements expected_matching_ids, response.results.map { |i| i.dig("_id").to_i }

      # 3) search for items without a value for the severity-💣-🔥 field.
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "no:severity-💣-🔥",
        source_fields: true,
      ).execute

      expected_matching_ids = [items[4].id]
      assert_same_elements expected_matching_ids, response.results.map { |i| i.dig("_id").to_i }
    end

    test "returns correct results for a query that filters by title", es_8_only: true do
      repo = create(:repository, owner: @user)
      issue = create(:issue, assignee: @user, repository: repo, title: "This has an unreated title")
      issue_2 = create(:issue, assignee: @user, repository: repo, title: "This is my favorite issue")
      issue_3 = create(:issue, assignee: @user, repository: repo, title: "This is my favorite issue also")
      item = create(:memex_project_item, content: issue, memex_project: @memex)
      item_2 = create(:memex_project_item, content: issue_2, memex_project: @memex)
      item_3 = create(:memex_project_item, content: issue_3, memex_project: @memex)
      populate_elasticsearch_index!([item, item_2, item_3])

      title_column = @memex.columns.find(&:title?)
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: 'title:"This is my favorite issue"', # showing title is treated as a keyword
        source_fields: true,
      ).execute

      assert_equal 1, response.total
      assert_equal issue_2.title, field_value(title_column.to_field, response.results.first)
    end

    test "returns correct results for a query that filters by multiple title values", es_8_only: true do
      repo = create(:repository, owner: @user)
      issue = create(:issue, assignee: @user, repository: repo, title: "This has an unreated title")
      issue_2 = create(:issue, assignee: @user, repository: repo, title: "This is my favorite issue")
      issue_3 = create(:issue, assignee: @user, repository: repo, title: "This is my favorite issue also")
      item = create(:memex_project_item, content: issue, memex_project: @memex)
      item_2 = create(:memex_project_item, content: issue_2, memex_project: @memex)
      item_3 = create(:memex_project_item, content: issue_3, memex_project: @memex)
      populate_elasticsearch_index!([item, item_2, item_3])

      title_column = @memex.columns.find(&:title?)
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: 'title:"This is my favorite issue","This has an unreated title"', # showing title is treated as a keyword
        source_fields: true,
      ).execute

      assert_equal 2, response.total
      found_issue_titles = [field_value(title_column.to_field, response.results.first), field_value(title_column.to_field, response.results.last)]
      assert_includes found_issue_titles, issue.title
      assert_includes found_issue_titles, issue_2.title
    end

    test "returns correct results for a query that filters by negative title", es_8_only: true do
      repo = create(:repository, owner: @user)
      issue = create(:issue, assignee: @user, repository: repo, title: "This has an unreated title")
      issue_2 = create(:issue, assignee: @user, repository: repo, title: "This is my favorite issue")
      issue_3 = create(:issue, assignee: @user, repository: repo, title: "This is my favorite issue also")
      item = create(:memex_project_item, content: issue, memex_project: @memex)
      item_2 = create(:memex_project_item, content: issue_2, memex_project: @memex)
      item_3 = create(:memex_project_item, content: issue_3, memex_project: @memex)
      populate_elasticsearch_index!([item, item_2, item_3])

      title_column = @memex.columns.find(&:title?)
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: '-title:"This is my favorite issue"', # showing title is treated as a keyword
        source_fields: true,
      ).execute

      assert_equal 2, response.total
      found_issue_titles = [field_value(title_column.to_field, response.results.first), field_value(title_column.to_field, response.results.last)]
      assert_includes found_issue_titles, issue.title
      assert_includes found_issue_titles, issue_3.title
    end

    test "correctly executes 'is:' content queries" do
      content_memex = create(:memex_project)
      user = create(:verified_user)
      repo = create(:repository, owner: user)
      open_issue = create(:issue, repository: repo, user: user, state: "open")
      closed_issue = create(:issue, repository: repo, user: user, state: "closed")
      open_pull = create(:pull_request, :disable_disk_access, repository: repo, user: user, head_ref: "open_pr")
      closed_pull = create(:pull_request, :closed, :disable_disk_access, repository: repo, user: user, head_ref: "closed_pr")
      merged_pull = create(:pull_request, :merged, :disable_disk_access, repository: repo, user: user, head_ref: "merged_pr")
      draft_pull = create(:pull_request, :disable_disk_access, repository: repo, user: user, draft: true, head_ref: "draft_pr")
      draft_issue = create(:draft_issue)

      open_issue_item = create(:memex_project_item, :archived, content: open_issue, memex_project: content_memex)
      closed_issue_item = create(:memex_project_item, :archived, content: closed_issue, memex_project: content_memex)
      open_pull_item = create(:memex_project_item, :archived, content: open_pull, memex_project: content_memex)
      closed_pull_item = create(:memex_project_item, :archived, content: closed_pull, memex_project: content_memex)
      merged_pull_item = create(:memex_project_item, :archived, content: merged_pull, memex_project: content_memex)
      draft_pull_item = create(:memex_project_item, :archived, content: draft_pull, memex_project: content_memex)
      draft_issue_item = create(:memex_project_item, :archived, content: draft_issue, memex_project: content_memex)

      content_items = [
        open_issue_item,
        closed_issue_item,
        open_pull_item,
        closed_pull_item,
        merged_pull_item,
        draft_pull_item,
        draft_issue_item,
      ]

      specs = [
        ["issue", [open_issue_item, closed_issue_item]],
        ["draft", [draft_issue_item, draft_pull_item]],
        ["pr", [open_pull_item, closed_pull_item, merged_pull_item, draft_pull_item]],
        ["open", [open_issue_item, open_pull_item, draft_pull_item, draft_issue_item]],
        ["closed", [closed_issue_item, closed_pull_item]],
        ["merged", [merged_pull_item]]
      ]

      populate_elasticsearch_index!(content_items)

      content_memex.reload

      specs.each do |is_query_value, expected_items|
        results = Search::Queries::MemexProjectItemQuery
          .new(
            project: content_memex,
            viewer: @user,
            items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
            query: "is:#{is_query_value}"
          )
          .execute
          .results

        assert_equal(
          expected_items.count,
          results.count,
          "should have received #{expected_items.count} items for is:#{is_query_value} query, but received #{results.count} instead"
        )

        expected_items_ids = expected_items.map(&:id).sort
        results_ids = results.map { |r| r.dig("_source", "database_id") }.sort

        assert_equal(
          expected_items_ids,
          results_ids,
          "should have received project items with ids: #{expected_items_ids} for is:#{is_query_value} query, but received #{results_ids} instead"
        )
      end
    end

    test "returns correct results for full text queries" do
      repo = create(:repository, owner: @user)

      issue_1 = create(:issue, repository: repo, title: "A very important issue")
      issue_2 = create(:issue, repository: repo, title: "This title has all different words")
      item_1 = create(:memex_project_item, content: issue_1, memex_project: @memex)
      item_2 = create(:memex_project_item, content: issue_2, memex_project: @memex)

      populate_elasticsearch_index!([item_1, item_2])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "very important"
      ).execute

      assert_equal 1, response.total
      assert_same_elements [item_1.id], response.results.map { |r| r["_source"]["database_id"] }
    end

    test "returns correct results for queries with special characters" do
      repo = create(:repository, owner: @user)

      issue_1 = create(:issue, repository: repo, title: "A boring title")
      issue_2 = create(:issue, repository: repo, title: "A title with special characters :-)")
      item_1 = create(:memex_project_item, content: issue_1, memex_project: @memex)
      item_2 = create(:memex_project_item, content: issue_2, memex_project: @memex)

      populate_elasticsearch_index!([item_1, item_2])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: ":-)"
      ).execute

      assert_equal 1, response.total
      assert_same_elements [item_2.id], response.results.map { |r| r["_source"]["database_id"] }
    end

    test "returns correct results for OR'ed empty value queries (no:field1,field2)" do
      issue_with_assignee = create(:issue, assignee: @user, repository: @repo)
      issue_with_assignee_2 = create(:issue, assignee: @user, repository: @repo)

      item_with_no_assignee_or_estimate = create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      item_with_assignee = create(:memex_project_item, content: issue_with_assignee, memex_project: @memex)
      item_with_estimate = create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      item_with_assignee_and_estimate = create(:memex_project_item, content: issue_with_assignee_2, memex_project: @memex)


      single_select_column = create(:single_select_memex_column, memex_project: @memex)
      [item_with_estimate, item_with_assignee_and_estimate].each do |item|
        create(
          :single_select_memex_project_column_value,
          value: single_select_column.settings["options"][0]["id"],
          memex_project_column: single_select_column,
          memex_project_item: item
        )
      end

      populate_elasticsearch_index!([item_with_no_assignee_or_estimate, item_with_assignee, item_with_estimate, item_with_assignee_and_estimate])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "no:estimate,assignee"
      ).execute

      expected_item_ids = [item_with_no_assignee_or_estimate, item_with_assignee, item_with_estimate].map { |item| item.id }

      assert_equal expected_item_ids.length, response.total
      assert_same_elements expected_item_ids, response.results.map { |r| r["_source"]["database_id"] }
    end

    test "returns correct results for AND'ed empty value queries (no:field1 no:field2)" do
      issue_with_assignee = create(:issue, assignee: @user, repository: @repo)
      issue_with_assignee_2 = create(:issue, assignee: @user, repository: @repo)

      item_with_no_assignee_or_estimate = create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      item_with_assignee = create(:memex_project_item, content: issue_with_assignee, memex_project: @memex)
      item_with_estimate = create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      item_with_assignee_and_estimate = create(:memex_project_item, content: issue_with_assignee_2, memex_project: @memex)


      single_select_column = create(:single_select_memex_column, memex_project: @memex)
      [item_with_estimate, item_with_assignee_and_estimate].each do |item|
        create(
          :single_select_memex_project_column_value,
          value: single_select_column.settings["options"][0]["id"],
          memex_project_column: single_select_column,
          memex_project_item: item
        )
      end

      populate_elasticsearch_index!([item_with_no_assignee_or_estimate, item_with_assignee, item_with_estimate, item_with_assignee_and_estimate])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "no:estimate no:assignee"
      ).execute

      expected_item_ids = [item_with_no_assignee_or_estimate].map { |item| item.id }

      assert_equal expected_item_ids.length, response.total
      assert_same_elements expected_item_ids, response.results.map { |r| r["_source"]["database_id"] }
    end

    test "returns correct results for OR'ed empty value queries combined with an additional fields' AND query (no:field1,field2 field3:value)", es_8_only: true do
      # no match
      item_with_no_assignee = create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      item_with_assignee_and_estimate_and_label = create(:memex_project_item, content: create(:issue, assignee: @user, repository: @repo, labels: [@label_bug]), memex_project: @memex)

      # matches
      item_with_assignee_and_label = create(:memex_project_item, content: create(:issue, assignee: @user, repository: @repo, labels: [@label_bug]), memex_project: @memex)
      item_with_assignee_and_estimate = create(:memex_project_item, content: create(:issue, assignee: @user, repository: @repo), memex_project: @memex)
      item_with_assignee_and_no_label_nor_estimate = create(:memex_project_item, content: create(:issue, assignee: @user, repository: @repo), memex_project: @memex)

      single_select_column = create(:single_select_memex_column, memex_project: @memex)
      [item_with_assignee_and_estimate_and_label, item_with_assignee_and_estimate].each do |item|
        create(
          :single_select_memex_project_column_value,
          value: single_select_column.settings["options"][0]["id"],
          memex_project_column: single_select_column,
          memex_project_item: item
        )
      end

      populate_elasticsearch_index!([
        item_with_no_assignee,
        item_with_assignee_and_estimate_and_label,
        item_with_assignee_and_label,
        item_with_assignee_and_estimate,
        item_with_assignee_and_no_label_nor_estimate,
      ])

      # test query qualifier order since initial bug reported in https://github.com/github/projects-platform/issues/1582 behaved differently depending on order they were provided
      ["no:estimate,label assignee:#{@user.login}", "assignee:#{@user.login} no:estimate,label"].each do |query|
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: query
        ).execute

        expected_item_ids = [
          item_with_assignee_and_label,
          item_with_assignee_and_estimate,
          item_with_assignee_and_no_label_nor_estimate
        ].map { |item| item.id }

        assert_equal expected_item_ids.length, response.total
        assert_same_elements expected_item_ids, response.results.map { |r| r["_source"]["database_id"] }
      end
    end

    test "allows filtering by issue number" do
      items = [
        create(:memex_project_item, content: create(:issue, title: "first", repository: @repo), memex_project: @memex),
        create(:memex_project_item, content: create(:issue, title: "second", repository: @repo), memex_project: @memex),
      ]

      populate_elasticsearch_index!(items)

      items.each do |item|
        number = item.content.number
        ["#{number}", "##{number}"].each do |number_query|
          response = Search::Queries::MemexProjectItemQuery.new(
            project: @memex.reload,
            viewer: @user,
            query: number_query
          ).execute

          assert_equal 1, response.total
          assert_equal item.id, response.results.first["_source"]["database_id"]
        end
      end
    end

    test "returns correct results for a query that filters by linked pull request", es_8_only: true do
      pull_requests = [
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
      ]

      linked_pr_items = @unarchived_items[0..2].map do |item|
        create(:close_issue_reference, issue: item.issue, pull_request: pull_requests[0])
        item
      end

      # Create a reference to the other PR and link it to a different item, to make sure that item is excluded from results
      create(:close_issue_reference, issue: @unarchived_items[3].issue, pull_request: pull_requests[1])

      populate_elasticsearch_index!(@unarchived_items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "linked-pull-requests:#{pull_requests[0].number}",
      ).execute

      assert_equal linked_pr_items.size, response.total
      assert_same_elements linked_pr_items.map(&:id), response.results.map { |result| result["_source"]["database_id"] }
    end

    test "does not do unexpected partial queries for linked pull requests" do
      pull_requests = [
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
      ]

      linked_pr_items = @unarchived_items[0..2].map do |item|
        create(:close_issue_reference, issue: item.issue, pull_request: pull_requests[0])
        item
      end

      # Create a reference to the other PR and link it to a different item, to make sure that item is excluded from results
      create(:close_issue_reference, issue: @unarchived_items[3].issue, pull_request: pull_requests[1])

      pull_requests[0].issue.update(number: 1)
      pull_requests[1].issue.update(number: 11)

      populate_elasticsearch_index!(@unarchived_items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "linked-pull-requests:1",
      ).execute

      assert_equal linked_pr_items.size, response.total
      assert_same_elements linked_pr_items.map(&:id), response.results.map { |result| result["_source"]["database_id"] }
    end

    test "returns correct results for a query that filters by multiple linked pull request values" do
      pull_requests = [
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
      ]

      linked_pr_1_items = @unarchived_items[0..2].map do |item|
        create(:close_issue_reference, issue: item.issue, pull_request: pull_requests[0])
        item
      end
      create(:close_issue_reference, issue: @unarchived_items[3].issue, pull_request: pull_requests[1])
      linked_pr_2_items = [@unarchived_items[3]]
      all_linked_items = linked_pr_1_items + linked_pr_2_items

      # Make sure there will be at least 1 item we don't expect to be returned in results
      assert all_linked_items.size < @unarchived_items.size

      populate_elasticsearch_index!(@unarchived_items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "linked-pull-requests:#{pull_requests[0].number},#{pull_requests[1].number}",
      ).execute

      assert_equal all_linked_items.size, response.total
      assert_same_elements all_linked_items.map(&:id), response.results.map { |result| result["_source"]["database_id"] }
    end

    test "returns correct results for a query that filters by negative linked pull request" do
      pull_requests = [
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
      ]

      linked_pr_1_items = @unarchived_items[0..2].map do |item|
        create(:close_issue_reference, issue: item.issue, pull_request: pull_requests[0])
        item
      end
      create(:close_issue_reference, issue: @unarchived_items[3].issue, pull_request: pull_requests[1])
      linked_pr_2_items = [@unarchived_items[3]]

      item_with_no_linked_pr = @unarchived_items[4]
      expected_items = linked_pr_2_items + [item_with_no_linked_pr]

      populate_elasticsearch_index!(@unarchived_items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "-linked-pull-requests:#{pull_requests[0].number}",
      ).execute

      assert_equal expected_items.size, response.total
      assert_same_elements expected_items.map(&:id), response.results.map { |result| result["_source"]["database_id"] }
    end

    test "returns correct results for a query that filters by linked pull request with wildcard" do
      pull_requests = [
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
      ]

      pull_requests[0].issue.update(number: 112)
      pull_requests[1].issue.update(number: 222)

      linked_pr_1_items = @unarchived_items[0..2].map do |item|
        create(:close_issue_reference, issue: item.issue, pull_request: pull_requests[0])
        item
      end
      create(:close_issue_reference, issue: @unarchived_items[3].issue, pull_request: pull_requests[1])
      linked_pr_2_items = [@unarchived_items[3]]
      all_linked_items = linked_pr_1_items + linked_pr_2_items

      populate_elasticsearch_index!(@unarchived_items)

      # Test trailing wildcard
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        # Match only items with linked PRs that start with "1" (i.e. PR with number 112)
        query: "linked-pull-requests:1*",
      ).execute

      assert_equal linked_pr_1_items.size, response.total
      assert_same_elements linked_pr_1_items.map(&:id), response.results.map { |result| result["_source"]["database_id"] }

      # Test leading wildcard
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        # Match only items with linked PRs that end with 2 (all items with linked PRs)
        query: "linked-pull-requests:*2",
      ).execute
      assert_equal all_linked_items.size, response.total
      assert_same_elements all_linked_items.map(&:id), response.results.map { |result| result["_source"]["database_id"] }

      # Test middle wildcard
      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        # Match only items with linked PRs that star with 1 and end with 2 (i.e. PR with number 112)
        query: "linked-pull-requests:1*2",
      ).execute
      assert_equal linked_pr_1_items.size, response.total
      assert_same_elements linked_pr_1_items.map(&:id), response.results.map { |result| result["_source"]["database_id"] }
    end

    test "returns correct results for a query that filters by negative linked pull request with wildcard" do
      pull_requests = [
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
      ]

      pull_requests[0].issue.update(number: 112)
      pull_requests[1].issue.update(number: 222)

      linked_pr_1_items = @unarchived_items[0..2].map do |item|
        create(:close_issue_reference, issue: item.issue, pull_request: pull_requests[0])
        item
      end
      create(:close_issue_reference, issue: @unarchived_items[3].issue, pull_request: pull_requests[1])
      expected_items = @unarchived_items[3..]

      populate_elasticsearch_index!(@unarchived_items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        # Match only items with linked PRs that start with "1" (i.e. PR with number 112)
        query: "-linked-pull-requests:1*",
      ).execute

      assert_equal expected_items.size, response.total
      assert_same_elements expected_items.map(&:id), response.results.map { |result| result["_source"]["database_id"] }
    end

    test "returns correct results for a query that filters by empty linked pull requests" do
      pull_request = create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}")

      @unarchived_items[0..-2].each do |item|
        create(:close_issue_reference, issue: item.issue, pull_request: pull_request)
      end

      item_with_no_linked_pr = @unarchived_items[-1]

      populate_elasticsearch_index!(@unarchived_items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: 'no:linked-pull-requests"',
      ).execute

      assert_equal 1, response.total
      assert_equal item_with_no_linked_pr.id, response.results.first["_source"]["database_id"]
    end

    test "returns results from a partial query string that matches at the beginning of an indexed term" do
      items = [
        create(:memex_project_item, content: create(:issue, title: "Only the best ingredients!"), memex_project: @memex),
        create(:memex_project_item, content: create(:issue, title: "The best of the rest"), memex_project: @memex)
      ]

      populate_elasticsearch_index!(items)

      %w(Ing Ingred Ingredient).each do |partial_query|
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query: partial_query,
        ).execute

        assert_equal 1, response.total
        assert_equal items.first.id, response.results.first["_source"]["database_id"]
      end

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "Ingxxxx",
      ).execute

      # Make sure that the search analyzer is sensitive to gibberish appended to an otherwise valid prefix.
      assert_equal 0, response.total

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "best ing",
      ).execute

      # Make sure that the index analyzer outputs shingles (multi-word terms), and that the search analyzer treats
      # the query term as an opaque unit.
      assert_equal 1, response.total
      assert_equal items.first.id, response.results.first["_source"]["database_id"]
    end

    test "returns the correct result for a query that matches a long title exactly" do
      items = [
        create(:memex_project_item, content: create(:issue, title: "Only the best ingredients!"), memex_project: @memex),
        create(:memex_project_item, content: create(:issue, title: "The best of the rest"), memex_project: @memex)
      ]

      populate_elasticsearch_index!(items)

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: items.first.content.title,
      ).execute

      assert_equal 1, response.total
      assert_equal items.first.id, response.results.first["_source"]["database_id"]
    end

    test "returns correct results for a query that matches the text in a code fence" do
      items = [
        create(:memex_project_item, content: create(:issue, title: "Here is the `code` that works"), memex_project: @memex),
        create(:memex_project_item, content: create(:issue, title: "Here is some other stuff"), memex_project: @memex)
      ]

      populate_elasticsearch_index!(items)

      ["`code`", "code", "the cod", "the `cod"].each do |query|
        response = Search::Queries::MemexProjectItemQuery.new(
          project: @memex.reload,
          viewer: @user,
          query:
        ).execute

        assert_equal 1, response.total
        assert_equal items.first.id, response.results.first["_source"]["database_id"]
      end
    end

    test "returns correct results for a query that filters on parent issue", es_8_only: true do
      parent_issue = create(:issue, title: "I am a parent issue", repository: @repo)
      parent_item = create(:memex_project_item, content: parent_issue, memex_project: @memex)
      child_issue = create(:issue, title: "I am a child issue", repository: @repo)
      child_item = create(:memex_project_item, content: child_issue, memex_project: @memex)

      create_hierarchy!("
      - #{parent_issue}
        - #{child_issue}
      ", issues: [parent_issue, child_issue])

      populate_elasticsearch_index!([parent_item, child_item])

      response = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        query: "parent-issue:#{parent_issue.nwo_reference(nil)}"
      ).execute

      assert_equal 1, response.total
      assert_equal child_item.id, response.results.first["_source"]["database_id"]
    end

    test "returns correct results for a query that filters by `last-updated`" do
      now = Time.zone.now

      items = 5.times.map do |n|
        create(:memex_project_item, memex_project: @memex, updated_at: now - n.days)
      end

      populate_elasticsearch_index!(items)

      (0..4).each do |n|
        query = "last-updated:#{n}days"
        response = Timecop.freeze(now) do
          Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            query:,
          ).execute
        end

        expected = T.must(items[(0 + n)..4]).map(&:id)
        actual = response.results.map { _1["_source"]["database_id"] }

        assert_same_elements expected, actual, "incorrect results for query: '#{query}'"
      end
    end

    test "returns correct results for a query that filters by `updated`" do
      now = Time.zone.now

      items = 5.times.map do |n|
        create(:memex_project_item, memex_project: @memex, updated_at: now - n.days)
      end

      populate_elasticsearch_index!(items)

      (0..4).each do |n|
        query = "updated:>=@today-#{n}d"
        response = Timecop.freeze(now) do
          Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            query:,
          ).execute
        end

        expected = T.must(items[0..n]).map(&:id)
        actual = response.results.map { _1["_source"]["database_id"] }

        assert_same_elements expected, actual, "incorrect results for query: '#{query}'"
      end
    end

    test "returns correct results for a query that filters by closed reason" do
      issues = [
        create(:issue, repository: @repo, user: @user).tap { |i| i.close(i.user) },
        create(:issue, repository: @repo, user: @user).tap { |i| i.close(i.user, attributes: { state_reason: :not_planned }) },
        create(:issue, repository: @repo, user: @user, state: :closed).tap { |i| assert i.reopen!(i.user) },
        create(:issue)
      ]
      items = issues.map { |content| create(:memex_project_item, memex_project: @memex, content:) }

      populate_elasticsearch_index!(items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "reason:completed,reopened",
      )

      response = query.execute

      expected = [items[0].id, items[2].id]
      actual = response.results.map { _1["_source"]["database_id"] }

      assert_same_elements expected, actual
    end
  end

  context "#initialize" do
    test "raises an error if page size is not an integer between 0 and 250" do
      [-1, 251].each do |invalid_per_page|
        assert_raises_with_message(
          Search::Queries::CursorPagination::ParameterError,
          ":first must be between 0 and 250",
        ) do
          Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
            first: invalid_per_page
          )
        end
      end

      # verify that 0 page size is supported for existing gh CLI contract, see https://github.com/github/projects-platform/issues/2215
      [0, 250].each do |valid_per_page|
        assert_nothing_raised do
          Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
            first: valid_per_page
          )
        end
      end
    end

    test "raises an error if :after is not a decodeable cursor" do
      assert_raises_with_message(
        Search::Queries::CursorPagination::ParameterError,
        ":after does not appear to be a valid cursor",
      ) do
        Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
          after: "nonsense",
        )
      end
    end

    test ":first is valid alias for :per_page" do
      first = 5
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        first: first,
      )
      assert_equal query.per_page, first + 1
      response = query.execute
      assert_equal response.per_page, first
    end

    test ":last is a valid alias for :per_page if :before is defined" do
      last = 5
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
        last: last,
        before: "Y3Vyc29yOnYyOpIAzQL0"
      )
      assert_equal query.per_page, last + 1
      response = query.execute
      assert_equal response.per_page, last
    end

    test "raises an error when provided incompatible page size params" do
      [
        [
          [5, nil, 5, nil],
          "Only one of :per_page, :last, or :first may be specified at a time",
        ],
        [
          [5, nil, nil, "Y3Vyc29yOnYyOpIAzQL0"],
          "Cannot use :first in conjunction with :before",
        ],
        [
          [nil, "Y3Vyc29yOnYyOpIAzQL0", 5, nil],
          "Cannot use :last in conjunction with :after",
        ],
        [
          [nil, "Y3Vyc29yOnYyOpIAzQL0", nil, "Y3Vyc29yOnYyOpIAzQL0"],
          "Cannot specify both :before and :after",
        ]
      ].each do |(first, after, last, before), expected_message|
        assert_raises_with_message(
          Search::Queries::CursorPagination::ParameterError,
          expected_message
        ) do
          Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            first:,
            last:,
            after:,
            before:,
          )
        end
      end
    end
  end

  context "#build_sort" do
    test "includes default sort values" do
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        sort: [
          { "archived_at": { missing: "_first" } },
          { "_score": {} },
        ],
      )
      expected_sort = [
        { archived_at: { order: "asc", missing: "_first" } }, # default :order added, user-inputted :missing maintained
        { _score: { order: "desc", missing: "_last" } }, # _score has different default :order
        { virtual_priority: { order: "desc", missing: "_last" } }, # defaults added
        { database_id: { order: "asc", missing: "_last" } }, # defaults added
      ]
      built_sort = query.build_sort
      assert_equal expected_sort, built_sort
    end
  end

  context "#build_filter_query" do
    test "includes redacted repo ids in filter query by default" do
      repo_id_filter = Search::Queries::MemexProjectItemQueryRedactor.new.repository_ids_query_fragment
      Search::Queries::MemexProjectItemQueryRedactor.any_instance.expects(:query_has_redacted_repo_ids?).returns(true)
      query = Search::Queries::MemexProjectItemQuery.new(project: @memex, viewer: @user)
      filter = query.build_filter_query(query: "", context: query.build_context)
      assert filter.dig(:bool, :filter).any? { _1 == repo_id_filter }
    end

    test "does not include redacted repo ids in filter query when intentionally suppressed" do
      repo_id_filter = Search::Queries::MemexProjectItemQueryRedactor.new.repository_ids_query_fragment
      Search::Queries::MemexProjectItemQueryRedactor.any_instance.expects(:query_has_redacted_repo_ids?).returns(true).at_most_once
      query = Search::Queries::MemexProjectItemQuery.new(project: @memex, viewer: @user)
      filter = query.build_filter_query(query: "", context: query.build_context, include_redacted_repo_ids: false)
      refute filter.dig(:bool, :filter).any? { _1 == repo_id_filter }
    end

    test "does not include redacted repo ids in filter query when no redacted repo ids found" do
      repo_id_filter = Search::Queries::MemexProjectItemQueryRedactor.new.repository_ids_query_fragment
      Search::Queries::MemexProjectItemQueryRedactor.any_instance.expects(:query_has_redacted_repo_ids?).returns(false)
      query = Search::Queries::MemexProjectItemQuery.new(project: @memex, viewer: @user)
      filter = query.build_filter_query(query: "", context: query.build_context, include_redacted_repo_ids: true)
      refute filter.dig(:bool, :filter).any? { _1 == repo_id_filter }
    end

    test "includes redacted repo ids in query_doc by default" do
      repo_id_filter = Search::Queries::MemexProjectItemQueryRedactor.new.repository_ids_query_fragment
      Search::Queries::MemexProjectItemQueryRedactor.any_instance.expects(:query_has_redacted_repo_ids?).returns(true)
      query = Search::Queries::MemexProjectItemQuery.new(project: @memex, viewer: @user)
      assert query.query_doc.dig(:bool, :filter).any? { _1 == repo_id_filter }
    end
  end

  context "#build_aggregations" do
    test "inlcudes only the respository_ids aggregation by default" do
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
      )
      assert_equal ["repository_ids"], query.aggregations
    end

    test "includes :group_by param in aggregations" do
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(field_object_or_id: @memex.status_column.id),
      )
      assert_same_elements ["repository_ids", @memex.status_column.id], query.aggregations
    end

    test "sets results size to 0 when aggregations are present" do
      # This test doesn't actually query Elasticsearch, but it does exercise code
      # that contains a version check.
      Elastomer::Indexes::MemexProjectItems.any_instance.stubs(:index_running_version_8_plus?).returns(true)
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(field_object_or_id: @memex.status_column.id),
      )
      assert query.aggregations?
      assert_equal 0, query.query_document[:size]
    end

    test "does not include empty groups for single select fields if include_empty_groups: false", es_8_only: true do
      option_names = T.let(%w[xyz aaa 123 _ccc BBB _DDD 10], T::Array[T.nilable(String)])
      single_select_column = create(
        :single_select_memex_column,
        memex_project: @memex,
        settings: { options: option_names.map { |name| { name: name, color: "GRAY" } } }
      )
      options = single_select_column.settings["options"]
      (@unarchived_items + @archived_items).each_with_index do |item, index|
        next if index == 0 # skip for no value group
        target_status_option = options[index % options.length]
        next if target_status_option["name"] == "xyz" # skip xyz so that we have an empty group
        item.set_column_value(single_select_column, target_status_option["id"], @user)
      end
      populate_elasticsearch_index!(@all_items)

      @memex.reload

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        items_scope: Search::Memex::Context::MemexProjectItemsScope::All,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: single_select_column.id,
          include_empty_groups: false
        ),
      )
      results = query.execute
      assert results.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
      groups = results.primary_groups&.nodes
      expected_groups = option_names << MemexProjectColumn::Groupable::MISSING_VALUE_GROUP_KEY
      expected_groups.delete("xyz") # we didn't add any values with xyz, so we don't expect it to be returned
      assert_equal expected_groups, T.must(groups).map(&:group_value)
    end

    test "maintains sort order of nested results", es_8_only: true do
      status_column = @memex.status_column
      target_status_option = status_column.settings["options"][0]
      @unarchived_items.each_with_index do |item|
        item.set_column_value(status_column, target_status_option["id"], @user)
      end
      populate_elasticsearch_index!(@all_items)

      title_column = @memex.columns.find(&:title?)
      sort = [title_column.to_field.sort_fragment(direction: "asc")]

      grouped_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(field_object_or_id: @memex.status_column.id),
        sort: sort
      )
      results = grouped_query.execute
      assert results.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
      first_group = T.must(grouped_query.execute.primary_groups&.nodes&.first)
      group_item_ids = first_group.paginated_items.map do |i|
        i.dig("_source", "database_id").to_i
      end
      assert_same_elements group_item_ids, @unarchived_items.map(&:id)

      filtered_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "status:#{target_status_option['name']}",
        sort: sort
      )
      filtered_response = filtered_query.execute
      filtered_item_ids = filtered_response.results.map do |i|
        i.dig("_source", "database_id").to_i
      end

      assert_equal group_item_ids, filtered_item_ids
    end

    test "grouped_items_page_size is set correctly by default for grouping single-select fields", es_8_only: true do
      status_column = @memex.status_column
      todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
      done_option_id = status_column.settings["options"].find { |o| o["name"] == "Done" }["id"]

      items = create_list(:memex_project_item, 4, memex_project: @memex)
      @unarchived_items[0].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[1].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[2].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[3].set_column_value(status_column, todo_option_id, @user)

      populate_elasticsearch_index!(@all_items)

      response = Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          grouping_options: MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: @memex.status_column.id,
            groups_page_size: 4,
          ),
        ).execute
      end
      groups = T.must(response.primary_groups&.nodes)

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = status_column.settings["options"].count + 1 # +1 for `nil` no-value group
      assert_equal 4, options_and_no_value_count

      # assert we have the expected groups
      # note that 'In Progress' is not included because no items have that value.
      expected_sorted_group_values = ["Todo", "Done", MemexProjectColumn::Groupable::MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_group_values, groups.map(&:group_value)

      # assert we have the expected group item counts
      # with a MAX_PAGE_SIZE = 10, grouped_items_page_size = (10 / 4).floor = 2
      # note that 3 items were actually provided a Done value above, but only 2 are fetched.
      expected_sorted_group_counts = [1, 2, 1]
      assert_equal expected_sorted_group_counts, groups.map { |g| g.paginated_items.count }
    end

    test "groups_page_size and grouped_items_page_size can be explicitly set for grouping single-select fields", es_8_only: true do
      status_column = @memex.status_column
      todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
      done_option_id = status_column.settings["options"].find { |o| o["name"] == "Done" }["id"]

      items = create_list(:memex_project_item, 4, memex_project: @memex)
      @unarchived_items[0].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[1].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[2].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[3].set_column_value(status_column, todo_option_id, @user)

      populate_elasticsearch_index!(@all_items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: @memex.status_column.id,
          groups_page_size: 2,
          grouped_items_page_size: 1,
        ),
      )
      groups = T.must(query.execute.primary_groups&.nodes)

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and _noValue.
      options_and_no_value_count = status_column.settings["options"].count + 1 # +1 for _noValue group
      assert_equal 4, options_and_no_value_count

      # assert we have the expected groups (just the first 2 as specified by groups_page_size)
      # note that 'In Progress' is not included because no items have that value.
      expected_sorted_group_values = %w[Todo Done]
      assert_equal expected_sorted_group_values, groups.map(&:group_value)

      # assert we have the expected group item counts (just 1 in each group, as specified by grouped_items_page_size)
      # note that 3 items were actually provided a Done value above, but only 2 are fetched.
      expected_sorted_group_counts = [1, 1]
      assert_equal expected_sorted_group_counts, groups.map { |g| g.paginated_items.count }
    end

    test "paginates grouped items based on priority sort value", es_8_only: true do
      status_column = @memex.status_column
      todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
      done_option_id = status_column.settings["options"].find { |o| o["name"] == "Done" }["id"]

      items = create_list(:memex_project_item, 4, memex_project: @memex)
      @unarchived_items[0].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[1].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[2].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[3].set_column_value(status_column, todo_option_id, @user)
      @unarchived_items[4].set_column_value(status_column, todo_option_id, @user)

      populate_elasticsearch_index!(@all_items)

      first_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: @memex.status_column.id,
          grouped_items_page_size: 2,
        ),
      ).execute

      # We requested only 2 items per group, so we we expect the 2 lowest priority items in each group.
      expected_done_item_ids = @unarchived_items[1..2].map(&:id).reverse
      expected_todo_item_ids = @unarchived_items[3..4].map(&:id).reverse

      todo_group = T.must(first_page.primary_groups&.nodes&.first)
      done_group = T.must(first_page.primary_groups&.nodes&.second)

      assert_same_elements expected_done_item_ids, done_group.paginated_items.map { |i| i.dig("_id").to_i }
      assert done_group.has_next_page
      assert done_group.end_cursor
      assert_same_elements expected_todo_item_ids, todo_group.paginated_items.map { |i| i.dig("_id").to_i }
      refute todo_group.has_next_page
      assert todo_group.end_cursor

      # Now we request a second page of Done items, verifying we get them.
      done_items_second_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "#{status_column.id}:Done",
        after: done_group.end_cursor
      ).execute

      expected_done_item_ids = [@unarchived_items[0]].map(&:id)
      assert_same_elements expected_done_item_ids, done_items_second_page.results.map { |i| i.dig("_id").to_i }
      refute done_items_second_page.has_next_page
      assert done_items_second_page.has_previous_page
      assert done_items_second_page.start_cursor
      assert done_items_second_page.end_cursor

      # Now we request a third page of Done items when there isn't one, verifying that we get an empty list.
      done_items_third_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "#{status_column.id}:Done",
        after: done_items_second_page.end_cursor
      ).execute

      expected_done_item_ids = []
      assert_same_elements expected_done_item_ids, done_items_third_page.results.map { |i| i.dig("_id").to_i }
      refute done_items_third_page.has_next_page
      refute done_items_third_page.has_previous_page
      refute done_items_third_page.start_cursor
      refute done_items_third_page.end_cursor
    end

    test "paginates forward through groups", es_8_only: true do
      a_user = create(:verified_user, login: "aaaa")
      b_user = create(:verified_user, login: "bbbb")
      c_user = create(:verified_user, login: "cccc")
      repo = create(:repository, owner: a_user)
      repo.add_member(b_user)
      repo.add_member(c_user)
      repo.add_member(@user)
      new_item = lambda do |assignee|
        issue = create(:issue, assignee: assignee, repository: repo)
        create(:memex_project_item, content: issue, memex_project: @memex)
      end
      items = [
        new_item.call(a_user),
        new_item.call(b_user),
        new_item.call(a_user),
        new_item.call(b_user),
        new_item.call(c_user),
        new_item.call(nil),
        new_item.call(c_user),
        new_item.call(nil),
      ]
      populate_elasticsearch_index!(items)

      assignee_col_id = @memex.columns.find(&:assignees?)&.id
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: assignee_col_id,
          groups_page_size: 2,
        ),
      )
      response = query.execute
      groups = response.primary_groups&.nodes

      assert_equal 2, T.must(groups).size
      assert_equal [a_user.login, b_user.login], T.must(groups).map(&:group_value)
      decoded_cursor = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(response.end_cursor)
      assert_equal ({ "bucket" => b_user.login }), decoded_cursor
      assert response.has_next_page
      refute response.has_previous_page

      next_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: assignee_col_id,
          groups_page_size: 2,
          cursor: response.end_cursor,
        )
      ).execute
      next_page_groups = T.must(next_page.primary_groups&.nodes)

      assert_equal 2, next_page_groups.size
      assert_equal [c_user.login, MemexProjectColumn::Groupable::MISSING_VALUE_GROUP_KEY], next_page_groups.map(&:group_value)
      next_cursor = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(next_page.end_cursor)
      assert_equal ({ "bucket" => nil }), next_cursor
      refute next_page.has_next_page
      assert next_page.has_previous_page
    end

    test "paginates forward through groups, with the 'no value' group first if specified", es_8_only: true do
      a_user = create(:verified_user, login: "aaaa")
      b_user = create(:verified_user, login: "bbbb")
      c_user = create(:verified_user, login: "cccc")
      repo = create(:repository, owner: a_user)
      repo.add_member(b_user)
      repo.add_member(c_user)
      repo.add_member(@user)
      new_item = lambda do |assignee|
        issue = create(:issue, assignee: assignee, repository: repo)
        create(:memex_project_item, content: issue, memex_project: @memex)
      end
      items = [
        new_item.call(a_user),
        new_item.call(b_user),
        new_item.call(a_user),
        new_item.call(b_user),
        new_item.call(c_user),
        new_item.call(nil),
        new_item.call(c_user),
        new_item.call(nil),
      ]
      populate_elasticsearch_index!(items)

      assignee_col_id = @memex.columns.find(&:assignees?)&.id
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: assignee_col_id,
          missing_value_group_order: MemexProjectColumn::Groupable::MissingValueGroupOrder::First,
          groups_page_size: 2,
        ),
      )
      response = query.execute
      groups = T.must(response.primary_groups&.nodes)
      assert_equal 2, groups.size
      assert_equal [MemexProjectColumn::Groupable::MISSING_VALUE_GROUP_KEY, a_user.login], groups.map(&:group_value)
      decoded_cursor = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(response.end_cursor)
      assert_equal ({ "bucket" => a_user.login }), decoded_cursor
      assert response.has_next_page
      refute response.has_previous_page

      next_page = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: assignee_col_id,
          missing_value_group_order: MemexProjectColumn::Groupable::MissingValueGroupOrder::First,
          groups_page_size: 2,
          cursor: response.end_cursor,
        ),
      ).execute
      groups = T.must(next_page.primary_groups&.nodes)
      assert_equal 2, groups.size
      assert_equal [b_user.login, c_user.login], groups.map(&:group_value)
      next_cursor = Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(next_page.end_cursor)
      assert_equal ({ "bucket" => c_user.login }), next_cursor
      refute next_page.has_next_page
      assert next_page.has_previous_page
    end

    test "group_ids are unique even if group_values are the same", es_8_only: true do
      status_column = @memex.status_column
      assignees_column = @memex.columns.find(&:assignees?)

      populate_elasticsearch_index!(@all_items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(field_object_or_id: @memex.status_column.id),
        items_scope: Search::Memex::Context::MemexProjectItemsScope::All,
      )
      status_response_groups = T.must(query.execute.primary_groups&.nodes)
      assert_equal 1, status_response_groups.size

      no_status_group_value = status_response_groups.first&.group_value
      no_status_group_id = status_response_groups.first&.group_id
      refute_nil no_status_group_id

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(field_object_or_id: assignees_column.id),
        items_scope: Search::Memex::Context::MemexProjectItemsScope::All,
      )
      assignees_response_groups = T.must(query.execute.primary_groups&.nodes)
      assert_equal 1, assignees_response_groups.size

      no_assignees_group_value = assignees_response_groups.first&.group_value
      no_assignees_group_id = assignees_response_groups.first&.group_id
      refute_nil no_assignees_group_id

      assert_equal no_status_group_value, no_assignees_group_value
      refute_equal no_status_group_id, no_assignees_group_id
    end
  end

  context "secondary_grouping" do
    test "returns expected primary and secondary group values, metadata, and counts for a static, single-select secondary group field, non-paginated", es_8_only: true do
      option_names = T.let(%w[Urgent Normal Meh], T::Array[T.nilable(String)])
      priority_column = create(
        :single_select_memex_column,
        memex_project: @memex,
        settings: { options: option_names.map { |name| { name: name, color: "GRAY" } } }
      )

      priority_options = priority_column.settings["options"]
      urgent = priority_options[0]["id"]
      normal = priority_options[1]["id"]
      meh = priority_options[2]["id"]

      status_column = @memex.status_column
      status_options = status_column.settings["options"]
      todo = status_options.find { |o| o["name"] == "Todo" }["id"]
      done = status_options.find { |o| o["name"] == "Done" }["id"]
      in_progress = status_options.find { |o| o["name"] == "In Progress" }["id"]

      items = 10.times.map do
        create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      end
      # items[0] has empty status and priority values
      set_column_values(items[1], [[status_column, in_progress], [priority_column, normal]])
      set_column_values(items[2], [[status_column, done], [priority_column, normal]])
      set_column_values(items[3], [[status_column, done], [priority_column, normal]])
      set_column_values(items[4], [[priority_column, normal]])
      set_column_values(items[5], [[priority_column, normal]])
      set_column_values(items[6], [[status_column, in_progress]])
      set_column_values(items[7], [[status_column, in_progress], [priority_column, urgent]])
      set_column_values(items[8], [[status_column, in_progress], [priority_column, urgent]])
      set_column_values(items[9], [[status_column, in_progress], [priority_column, urgent]])

      populate_elasticsearch_index!(items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: status_column.id,
          include_empty_groups: true,
          include_group_metadata: true,
          missing_value_group_order: MemexProjectColumn::Groupable::MissingValueGroupOrder::First,
          secondary_grouping_options: MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: priority_column.id,
            include_empty_groups: false,
            include_group_metadata: true,
          )
        )
      )
      response = query.execute
      assert response.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
      response = T.cast(response, Search::Responses::GroupedMemexProjectItemResponse)

      primary_groups_values = response.primary_groups.nodes.map(&:group_value)
      primary_group_metadata = response.primary_groups.nodes.map(&:metadata)
      primary_groups_counts = response.primary_groups.nodes.map(&:total_count)
      secondary_groups_values = response.secondary_groups&.nodes&.map(&:group_value)
      secondary_group_metadata = response.secondary_groups&.nodes&.map(&:metadata)
      secondary_groups_counts = response.secondary_groups&.nodes&.map(&:total_count)

      # Primary: Empty primary group "Todo" (vertical) to be included in results, with MISSING first
      assert_equal [MISSING_VALUE_GROUP_KEY, "Todo", "In Progress", "Done"], primary_groups_values
      assert_equal [nil, "Todo", "In Progress", "Done"], primary_group_metadata.map { |m| m ? m.group_metadata[:name] : nil }
      assert_equal [3, 0, 5, 2], primary_groups_counts

      # Secondary: Empty secondary group "Meh" (horizontal) to be excluded in results, with MISSING last
      assert_equal ["Urgent", "Normal", MISSING_VALUE_GROUP_KEY], secondary_groups_values
      assert_equal ["Urgent", "Normal", nil], secondary_group_metadata&.map { |m| m ? m.group_metadata[:name] : nil }
      assert_equal [3, 5, 2], secondary_groups_counts

      # Now let's verify each "cell" of items at the intersection of primary and secondary groups.
      expected_grouped_item_values = [
        ["In Progress", "Urgent", 3],
        [MISSING_VALUE_GROUP_KEY, "Normal", 2],
        ["In Progress", "Normal", 1],
        ["Done", "Normal", 2],
        [MISSING_VALUE_GROUP_KEY, MISSING_VALUE_GROUP_KEY, 1],
        ["In Progress", MISSING_VALUE_GROUP_KEY, 1]
      ]

      assert_equal expected_grouped_item_values.count, response.grouped_items&.count

      grouped_items = response.grouped_items&.each_with_index do |g, i|
        actual_grouped_item_values = [g.group_value, g.secondary_group_value, g.total_count]
        assert_equal expected_grouped_item_values[i], actual_grouped_item_values
      end
    end

    test "returns expected primary and secondary group values, metadata, and counts for a non-static, Assignee secondary group field, non-paginated", es_8_only: true do
      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "stimpy")
      user_george = create(:verified_user, login: "george")
      @repo.add_member(user_ren)
      @repo.add_member(user_stimpy)
      @repo.add_member(user_george)
      assignee_column = @memex.columns.find(&:assignees?)

      status_column = @memex.status_column
      status_options = status_column.settings["options"]
      todo = status_options.find { |o| o["name"] == "Todo" }["id"]
      done = status_options.find { |o| o["name"] == "Done" }["id"]
      in_progress = status_options.find { |o| o["name"] == "In Progress" }["id"]

      items = 10.times.map do
        create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      end
      # items[0] has empty status and assignee values
      set_column_values(items[1], [[status_column, in_progress], [assignee_column, user_ren.id]])
      set_column_values(items[2], [[status_column, done], [assignee_column, user_ren.id]])
      set_column_values(items[3], [[status_column, done], [assignee_column, user_ren.id]])
      set_column_values(items[4], [[assignee_column, user_ren.id]])
      set_column_values(items[5], [[assignee_column, user_ren.id]])
      set_column_values(items[6], [[status_column, in_progress]])
      set_column_values(items[7], [[status_column, in_progress], [assignee_column, user_stimpy.id]])
      set_column_values(items[8], [[status_column, in_progress], [assignee_column, user_stimpy.id]])
      set_column_values(items[9], [[status_column, in_progress], [assignee_column, user_stimpy.id]])

      populate_elasticsearch_index!(items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: status_column.id,
          include_empty_groups: true,
          include_group_metadata: true,
          missing_value_group_order: MemexProjectColumn::Groupable::MissingValueGroupOrder::First,
          secondary_grouping_options: MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: assignee_column.id,
            include_group_metadata: true,
          )
        )
      )
      response = query.execute
      assert response.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
      response = T.cast(response, Search::Responses::GroupedMemexProjectItemResponse)

      primary_groups_values = response.primary_groups.nodes.map(&:group_value)
      primary_group_metadata = response.primary_groups.nodes.map(&:metadata)
      primary_groups_counts = response.primary_groups.nodes.map(&:total_count)
      secondary_groups_values = response.secondary_groups&.nodes&.map(&:group_value)
      secondary_group_metadata = response.secondary_groups&.nodes&.map(&:metadata)
      secondary_groups_counts = response.secondary_groups&.nodes&.map(&:total_count)

      # Primary: Empty primary group "Todo" (vertical) to be included in results, with MISSING first
      assert_equal [MISSING_VALUE_GROUP_KEY, "Todo", "In Progress", "Done"], primary_groups_values
      assert_equal [nil, "Todo", "In Progress", "Done"], primary_group_metadata.map { |m| m ? m.group_metadata[:name] : nil }
      assert_equal [3, 0, 5, 2], primary_groups_counts

      # Secondary: Empty secondary group "george" (horizontal) to be excluded in results, with MISSING last
      assert_equal ["ren", "stimpy", MISSING_VALUE_GROUP_KEY], secondary_groups_values
      assert_equal ["ren", "stimpy", nil], secondary_group_metadata&.map { |m| m ? m.group_metadata[:login] : nil }
      assert_equal [5, 3, 2], secondary_groups_counts

      # Now let's verify each "cell" of items at the intersection of primary and secondary groups.
      expected_grouped_item_values = [
        [MISSING_VALUE_GROUP_KEY, "ren", 2],
        ["In Progress", "ren", 1],
        ["Done", "ren", 2],
        ["In Progress", "stimpy", 3],
        [MISSING_VALUE_GROUP_KEY, MISSING_VALUE_GROUP_KEY, 1],
        ["In Progress", MISSING_VALUE_GROUP_KEY, 1]
      ]

      assert_equal expected_grouped_item_values.count, response.grouped_items&.count

      grouped_items = response.grouped_items&.each_with_index do |g, i|
        actual_grouped_item_values = [g.group_value, g.secondary_group_value, g.total_count]
        assert_equal expected_grouped_item_values[i], actual_grouped_item_values
      end
    end

    test "returns expected groups and grouped_items when provided primary and secondary group cursors", es_8_only: true do
      create_items_with_status_and_priority_columns => { items:, status_column:, priority_column: }
      assert_equal 13, items.size

      populate_elasticsearch_index!(items)

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex.reload,
        viewer: @user,
        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: status_column.id,
          include_empty_groups: true,
          missing_value_group_order: MemexProjectColumn::Groupable::MissingValueGroupOrder::First,
          groups_page_size: 2,
          secondary_grouping_options: MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: priority_column.id,
            include_empty_groups: false,
            groups_page_size: 2,
          )
        )
      )
      response = query.execute
      assert response.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
      response = T.cast(response, Search::Responses::GroupedMemexProjectItemResponse)

      expected_primary_page_1 = %w[_noValue Todo]
      expected_secondary_page_1 = %w[Urgent Normal]

      assert_equal expected_primary_page_1, response.primary_groups.nodes.map { _1.group_value }
      assert_equal expected_secondary_page_1, response.secondary_groups&.nodes&.map { _1.group_value }

      assert response.primary_groups.has_next_page
      assert response.secondary_groups&.has_next_page

      primary_group_ids = response.primary_groups.nodes.map { _1.group_id }
      secondary_group_ids = response.secondary_groups&.nodes&.map { _1.group_id }

      assert response.grouped_items&.all? { primary_group_ids.include? _1.group_id }
      assert response.grouped_items&.all? { secondary_group_ids&.include? _1.secondary_group_id }

      assert_equal 2, response.grouped_items&.count
      # Todo x Urgent
      # Todo x Normal
      # 'No Status' doesn't intersect with Urgent or Normal

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,

        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: status_column.id,
          include_empty_groups: true,
          missing_value_group_order: MemexProjectColumn::Groupable::MissingValueGroupOrder::First,
          groups_page_size: 2,
          cursor: response.primary_groups.end_cursor,
          secondary_grouping_options: MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: priority_column.id,
            include_empty_groups: false,
            groups_page_size: 2,
            cursor: response.secondary_groups&.end_cursor,
          )
        )
      )

      expected_primary_page_2 = ["In Progress", "Done"]
      expected_secondary_page_2 = %w[Meh _noValue]

      page_2 = query.execute
      assert page_2.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
      page_2 = T.cast(page_2, Search::Responses::GroupedMemexProjectItemResponse)

      assert_equal expected_primary_page_2, page_2.primary_groups.nodes.map { _1.group_value }
      assert_equal expected_secondary_page_2, page_2.secondary_groups&.nodes&.map { _1.group_value }

      primary_group_ids_page_2 = page_2.primary_groups.nodes.map { _1.group_id }
      secondary_group_ids_page_2 = page_2.secondary_groups&.nodes&.map { _1.group_id }

      assert page_2.grouped_items&.all? { primary_group_ids_page_2.include? _1.group_id }
      assert page_2.grouped_items&.all? { secondary_group_ids_page_2&.include? _1.secondary_group_id }

      assert_equal 4, page_2.grouped_items&.count
      # In Progress x Meh
      # In Progress x No Priority
      # Done x Meh
      # Done x No Priority
    end

    test "returns expected groups and grouped_items when provided just a primary group cursor", es_8_only: true do
      create_items_with_status_and_priority_columns => { items:, status_column:, priority_column: }
      assert_equal 13, items.size

      populate_elasticsearch_index!(items)

      primary_cursor = MemexProjectColumn::Groupable::Group.encode_cursor({ "bucket" => "Todo" })

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,

        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: status_column.id,
          include_empty_groups: true,
          missing_value_group_order: MemexProjectColumn::Groupable::MissingValueGroupOrder::First,
          groups_page_size: 2,
          cursor: primary_cursor,
          secondary_grouping_options: MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: priority_column.id,
            include_empty_groups: false,
            groups_page_size: 2,
            cursor: nil,
          )
        )
      )

      expected_primary_groups = ["In Progress", "Done"]
      expected_secondary_groups = %w[Urgent Normal]

      response = query.execute
      assert response.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
      response = T.cast(response, Search::Responses::GroupedMemexProjectItemResponse)

      assert_equal expected_primary_groups, response.primary_groups.nodes.map { _1.group_value }
      assert_equal expected_secondary_groups, response.secondary_groups&.nodes&.map { _1.group_value }

      primary_group_ids = response.primary_groups.nodes.map { _1.group_id }
      secondary_group_ids = response.secondary_groups&.nodes&.map { _1.group_id }

      assert response.grouped_items&.all? { primary_group_ids.include? _1.group_id }
      assert response.grouped_items&.all? { secondary_group_ids&.include? _1.secondary_group_id }

      assert_equal 4, response.grouped_items&.count
      # In Progress x Urgent
      # In Progress x Normal
      # Done x Urgent
      # Done x Normal
    end

    test "returns expected groups and grouped_items when provided just a secondary group cursor", es_8_only: true do
      create_items_with_status_and_priority_columns => { items:, status_column:, priority_column: }
      assert_equal 13, items.size

      populate_elasticsearch_index!(items)

      secondary_cursor = MemexProjectColumn::Groupable::Group.encode_cursor({ "bucket" => "Normal" })

      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,

        grouping_options: MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: status_column.id,
          include_empty_groups: true,
          missing_value_group_order: MemexProjectColumn::Groupable::MissingValueGroupOrder::First,
          groups_page_size: 2,
          cursor: nil,
          secondary_grouping_options: MemexProjectColumn::Groupable::Options.new(
            field_object_or_id: priority_column.id,
            include_empty_groups: false,
            groups_page_size: 2,
            cursor: secondary_cursor,
          )
        )
      )

      expected_primary_groups = %w[_noValue Todo]
      expected_secondary_groups = %w[Meh _noValue]

      response = query.execute
      assert response.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
      response = T.cast(response, Search::Responses::GroupedMemexProjectItemResponse)

      assert_equal expected_primary_groups, response.primary_groups.nodes.map { _1.group_value }
      assert_equal expected_secondary_groups, response.secondary_groups&.nodes&.map { _1.group_value }

      primary_group_ids = response.primary_groups.nodes.map { _1.group_id }
      secondary_group_ids = response.secondary_groups&.nodes&.map { _1.group_id }

      assert response.grouped_items&.all? { primary_group_ids.include? _1.group_id }
      assert response.grouped_items&.all? { secondary_group_ids&.include? _1.secondary_group_id }

      assert_equal 3, response.grouped_items&.count
      # 'No Status' doesn't intersect with Meh
      # No Status x No Priority
      # Todo x Meh
      # Todo x No Priority
    end
  end

  context "slice_by" do
    test "slices by single-select values, with or without a slice_value selected", es_8_only: true do

      status_column = @memex.status_column
      todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
      done_option_id = status_column.settings["options"].find { |o| o["name"] == "Done" }["id"]

      items = create_list(:memex_project_item, 4, memex_project: @memex)
      @unarchived_items[0].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[1].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[2].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[3].set_column_value(status_column, todo_option_id, @user)

      populate_elasticsearch_index!(@all_items)

      # 1) Slice by the Status field, without a slice_value specified
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: @memex.status_column.id,
        )
        response = query.execute
      end

      # sanity check that we have 4 Status options: Todo, In Progress, Done, and nil.
      options_and_no_value_count = status_column.settings["options"].count + 1 # +1 for _noValue slice
      assert_equal 4, options_and_no_value_count

      # assert we have the expected slice values
      # Note that 'In Progress' is not included because no items have that value.
      # Also note that 'Todo' is correctly ordered before 'Done', with missing last.
      expected_sorted_slice_values = ["Todo", "Done", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_slice_values, response&.slices&.map { |s| s["slice_value"] }

      # assert we have the expected slice item counts
      expected_sorted_slice_counts = [1, 3, 1]
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # 2) Slice by the Status field, with a slice_value specified
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: @memex.status_column.id,
          slice_value: "Done"
        )
        response = query.execute
      end

      # assert we still have the same expected slice values and counts
      assert_equal expected_sorted_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }
    end

    test "includes empty slices for known single-select values, with or without a filter or slice_value selected", es_8_only: true do

      status_column = @memex.status_column
      todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
      done_option_id = status_column.settings["options"].find { |o| o["name"] == "Done" }["id"]

      items = create_list(:memex_project_item, 4, memex_project: @memex)
      @unarchived_items[0].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[1].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[2].set_column_value(status_column, done_option_id, @user)
      @unarchived_items[3].set_column_value(status_column, todo_option_id, @user)

      populate_elasticsearch_index!(@all_items)

      # 1) Slice by the Status field, without a slice_value specified
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: @memex.status_column.id,
          include_empty_slices: true
        )
        response = query.execute
      end

      # assert we have the expected slice values and counts
      # Note that 'In Progress' is included last since it's a known slice value but empty
      expected_sorted_slice_values = ["Todo", "Done", MISSING_VALUE_GROUP_KEY, "In Progress"]
      expected_sorted_slice_counts = [1, 3, 1, 0]
      assert_equal expected_sorted_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # 2) Now also include a selected slice_value "Done"
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: @memex.status_column.id,
          slice_value: "Done",
          include_empty_slices: true
        )
        response = query.execute
      end

      # assert we still have the same expected slice values and counts
      assert_equal expected_sorted_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # 3) Now also filter on "Done" to change the slice counts based on the view filter
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          query: "status:Done",
          slice_by: @memex.status_column.id,
          slice_value: "Done",
          include_empty_slices: true
        )
        response = query.execute
      end

      # assert we have updated slice values and counts that match the view filter
      expected_sorted_slice_values = ["Done", "Todo", "In Progress", MISSING_VALUE_GROUP_KEY]
      expected_sorted_slice_counts = [3, 0, 0, 0]
      assert_equal expected_sorted_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }
    end

    test "includes empty slices for unknown Assignee values, with or without a filter or slice_value selected", es_8_only: true do
      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "stimpy")
      user_george = create(:verified_user, login: "george")
      user_horse = create(:verified_user, login: "horse")
      @repo.add_member(user_ren)
      @repo.add_member(user_stimpy)
      @repo.add_member(user_george)
      @repo.add_member(user_horse)
      assignee_col_id = @memex.columns.find(&:assignees?)&.id

      status_column = @memex.status_column
      todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
      done_option_id = status_column.settings["options"].find { |o| o["name"] == "Done" }["id"]
      progress_option_id = status_column.settings["options"].find { |o| o["name"] == "In Progress" }["id"]

      items = Array[create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)] #0
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @repo), memex_project: @memex) #1
      item.set_column_value(status_column, done_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_george], repository: @repo), memex_project: @memex) #2
      item.set_column_value(status_column, progress_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #3
      item.set_column_value(status_column, done_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #4
      item.set_column_value(status_column, todo_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @repo), memex_project: @memex) #5
      item.set_column_value(status_column, done_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_george, user_stimpy, user_horse, user_ren], repository: @repo), memex_project: @memex) #6
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #7
      item.set_column_value(status_column, done_option_id, @user)

      populate_elasticsearch_index!(items)

      # 1) Slice by the Assignee field, without a slice_value specified
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: assignee_col_id,
          include_empty_slices: true
        )
        response = query.execute
      end

      # assert we have the expected slice values and counts
      expected_sorted_slice_values = [user_george.login, user_horse.login, user_ren.login, user_stimpy.login, MISSING_VALUE_GROUP_KEY]
      expected_sorted_slice_counts = [2, 1, 5, 3, 1]
      assert_equal expected_sorted_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # 2) Now also include a selected slice_value "ren"
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: assignee_col_id,
          slice_value: user_ren.login,
          include_empty_slices: true
        )
        response = query.execute
      end

      # assert we still have the same expected slice values and counts
      assert_equal expected_sorted_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # 3) Now filter on Status "Done" to change the slice counts based on the view filter, with no slice value
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          query: "status:Done",
          slice_by: assignee_col_id,
          include_empty_slices: true
        )
        response = query.execute
      end

      # assert we have updated slice values and counts that match the view filter
      expected_sorted_slice_values = [user_ren.login, user_stimpy.login, user_george.login, user_horse.login, MISSING_VALUE_GROUP_KEY]
      expected_sorted_slice_counts = [3, 2, 0, 0, 0]
      assert_equal expected_sorted_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # 4) Now also include a selected slice_value "ren" along with the "Done" filter
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          query: "status:Done",
          slice_by: assignee_col_id,
          slice_value: user_ren.login,
          include_empty_slices: true
        )
        response = query.execute
      end

      # assert we still have the same expected slice values and counts
      assert_equal expected_sorted_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }
    end

    test "slices by assignee values with multiple assignees in separate slices" do
      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "Stimpy") # Notice the uppercase S here
      user_george = create(:verified_user, login: "george")
      @repo.add_member(user_ren)
      @repo.add_member(user_stimpy)
      @repo.add_member(user_george)
      assignee_col_id = @memex.columns.find(&:assignees?)&.id

      items = Array[create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)]
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @repo), memex_project: @memex)
      items << create(:memex_project_item, content: create(:issue, assignees: [user_george], repository: @repo), memex_project: @memex)
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex)
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex)
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @repo), memex_project: @memex)
      items << create(:memex_project_item, content: create(:issue, assignees: [user_george, user_stimpy, user_ren], repository: @repo), memex_project: @memex)

      populate_elasticsearch_index!(items)

      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: assignee_col_id,
        )
        response = query.execute
      end

      # Assert we have the expected slice values
      # By default, these are alpahebetically sorted, with the missing slice value last (i.e., no Assignee)
      # Unfortunately, everyting in Elasticsearch is cases sensitive for now, so uppercase "Stimpy" comes before lowercase users.
      expected_sorted_assignee_values = ["Stimpy", "george", "ren", MISSING_VALUE_GROUP_KEY]
      assert_equal expected_sorted_assignee_values, response&.slices&.map { |s| s["slice_value"] }

      # Assert we have the expected slice item counts
      expected_sorted_slice_counts = [3, 2, 4, 1]
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }
    end

    test "Redacts slices and items, slicing by Assignees, with or without slice_value", es_8_only: true do
      private_repo_admin = create(:user)
      private_repo = create(:private_repository, owner: private_repo_admin)

      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "stimpy")
      user_george = create(:verified_user, login: "george")
      user_muddy = create(:verified_user, login: "muddy")
      private_repo.add_member(user_george)
      private_repo.add_member(user_muddy)
      @repo.add_member(user_ren)
      @repo.add_member(user_stimpy)
      @repo.add_member(user_george)
      @repo.add_member(user_muddy)
      assignee_col_id = @memex.columns.find(&:assignees?)&.id

      items = Array[create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)] #0
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @repo), memex_project: @memex) #1
      items << create(:memex_project_item, content: create(:issue, assignees: [user_george, user_muddy], repository: private_repo), memex_project: @memex) #2 - redacted private_repo
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #3
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #4
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @repo), memex_project: @memex) #5
      items << create(:memex_project_item, content: create(:issue, assignees: [user_george, user_stimpy, user_ren], repository: @repo), memex_project: @memex) #6

      populate_elasticsearch_index!(items)

      # 4 non-zero Assignee values in the project view filter, excluding "muddy" who is only in the redacted private_repo item.
      # Slice values and counts do not change regardless of the slice_value applied to the query.
      # Counts do not include contributions from redacted items (hence only 1 for george)
      expected_slice_values = [user_george.login, user_ren.login, user_stimpy.login, MISSING_VALUE_GROUP_KEY]
      expected_sorted_slice_counts = [1, 4, 3, 1]

      # 1) Slice on Assignees, without a slice_value
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: assignee_col_id,
        )
        response = query.execute
      end

      # Assert we have the expected redacted slice values and counts
      assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # Assert we have the expected items (omitting the redacted item)
      assert_equal items.values_at(0, 1, 3, 4, 5, 6).map(&:id), response&.results&.map { |r| r["_id"].to_i }

      # 2) Slice on Assignees, with a slice_value "george"
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      Search::Queries::MemexProjectItemQuery.stub_const(:MAX_PAGE_SIZE, 10) do
        query = Search::Queries::MemexProjectItemQuery.new(
          project: @memex,
          viewer: @user,
          slice_by: assignee_col_id,
          slice_value: user_george.login
        )
        response = query.execute
      end

      # Assert we have the same expected redacted slice values and counts
      assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }
      assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }

      # Assert we have the expected items (omitting the redacted item).  Just the one for "george"
      assert_equal items.values_at(6).map(&:id), response&.results&.map { |r| r["_id"].to_i }
    end

    test "paginates items on slice_value for the Assignee field, and includes all slices in the response", es_8_only: true do
      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "stimpy")
      user_george = create(:verified_user, login: "george")
      user_horse = create(:verified_user, login: "horse")
      @repo.add_member(user_ren)
      @repo.add_member(user_stimpy)
      @repo.add_member(user_george)
      @repo.add_member(user_horse)
      assignee_col_id = @memex.columns.find(&:assignees?)&.id

      items = Array[create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)] #0
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @repo), memex_project: @memex) #1
      items << create(:memex_project_item, content: create(:issue, assignees: [user_george], repository: @repo), memex_project: @memex) #2
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #3
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #4
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @repo), memex_project: @memex) #5
      items << create(:memex_project_item, content: create(:issue, assignees: [user_george, user_stimpy, user_horse, user_ren], repository: @repo), memex_project: @memex) #6

      populate_elasticsearch_index!(items)

      # 1) Query with only slice_by to get assignee slice values and non-sliced items
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        slice_by: assignee_col_id,
      )
      response = query.execute

      # Assert we have 7 project items in the response,
      # 5 slices exist: each unique assignee (+ no assignee) for all items matching the Elasticsearch query,
      # and 4 items matching slice_value "ren" as the assignee.
      assert_equal 7, response.total
      assert_equal 5, response.slices&.size
      assert_equal 4, response.slices&.find { |s| s.dig("slice_value") == user_ren.login }&.dig("total_count")

      # 2) Fetch the first page of 2 items where "ren" is an assignee using the slice_value
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        slice_by: assignee_col_id,
        slice_value: user_ren.login,
        first: 2
      )
      response = query.execute

      # Assert we have the first 2 of 4 "ren" items, and all 5 slices still exist in the response.
      assert_equal 4, response.total
      assert_equal 5, response.slices&.size
      assert_equal items[3..4]&.map(&:id), response.results.map { |r| r["_id"].to_i }
      assert response.end_cursor
      assert response.has_next_page

      # 3) Fetch the last page of 2 items where "ren" is an assignee using the slice_value
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        slice_by: assignee_col_id,
        slice_value: user_ren.login,
        first: 2,
        after: response.end_cursor
      )
      response = query.execute

      # Assert we have the last 2 of 4 "ren" items, and all 5 slices still exist in the response.
      assert_equal 4, response.total
      assert_equal 5, response.slices&.size
      assert_equal items[5..6]&.map(&:id), response.results.map { |r| r["_id"].to_i }
      refute response.has_next_page
    end

    test "paginates items grouped by Status, on slice_value for the Assignee field, and includes all slices in the grouped response", es_8_only: true do
      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "stimpy")
      user_george = create(:verified_user, login: "george")
      user_horse = create(:verified_user, login: "horse")
      @repo.add_member(user_ren)
      @repo.add_member(user_stimpy)
      @repo.add_member(user_george)
      @repo.add_member(user_horse)
      assignee_col_id = @memex.columns.find(&:assignees?)&.id

      status_column = @memex.status_column
      todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
      done_option_id = status_column.settings["options"].find { |o| o["name"] == "Done" }["id"]
      progress_option_id = status_column.settings["options"].find { |o| o["name"] == "In Progress" }["id"]

      items = Array[create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)] #0
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @repo), memex_project: @memex) #1
      item.set_column_value(status_column, done_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_george], repository: @repo), memex_project: @memex) #2
      item.set_column_value(status_column, progress_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #3
      item.set_column_value(status_column, done_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #4
      item.set_column_value(status_column, todo_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @repo), memex_project: @memex) #5
      item.set_column_value(status_column, done_option_id, @user)
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_george, user_stimpy, user_horse, user_ren], repository: @repo), memex_project: @memex) #6
      items << item = create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #7
      item.set_column_value(status_column, done_option_id, @user)

      populate_elasticsearch_index!(items)

      # 1) Query with only slice_by to get assignee slice values and non-sliced, grouped items
      response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        slice_by: assignee_col_id,
        grouping_options: MemexProjectColumn::Groupable::Options.new(field_object_or_id: status_column.id),
      )
      response = query.execute
      assert response.is_a?(Search::Responses::GroupedMemexProjectItemResponse)

      # All 5 non-zero Assignee values in the project view filter.
      # Slice values and counts do not change regardless of slice_value or group_value applied to the query.
      expected_slice_values = [user_george.login, user_horse.login, user_ren.login, user_stimpy.login, MISSING_VALUE_GROUP_KEY]
      expected_ren_slice_count = 5

      # Assert we have 8 project items in the response.
      # Assert we have the expected slice values and counts.
      # Assert a grouped item response.
      assert_equal 8, response.total
      assert_equal expected_slice_values, response.slices&.map { |s| s["slice_value"] }
      assert_equal expected_ren_slice_count, response.slices&.find { |s| s.dig("slice_value") == user_ren.login }&.dig("total_count")
      assert_equal ["Todo", "In Progress", "Done", "_noValue"], T.must(response.primary_groups).nodes.map(&:group_value)

      # 2) Fetch the grouped items where "ren" is an assignee using the slice_value
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        slice_by: assignee_col_id,
        slice_value: user_ren.login,
        grouping_options: MemexProjectColumn::Groupable::Options.new(field_object_or_id: status_column.id),
      )
      response = query.execute

      # Assert we have 5 "ren" project items in the response,
      # Assert we have the same expected slice values and counts.
      # Grouped item response now excludes "In Progress" since "ren" is lazy with nothing In Progress.
      assert_equal 5, response.total
      assert_equal expected_slice_values, response.slices&.map { |s| s["slice_value"] }
      assert_equal expected_ren_slice_count, response.slices&.find { |s| s.dig("slice_value") == user_ren.login }&.dig("total_count")
      assert response.is_a?(Search::Responses::GroupedMemexProjectItemResponse)
      assert_equal %w[Todo Done _noValue], T.must(response.primary_groups).nodes.map(&:group_value)

      # 3) Fetch the first page of 2 "Done" group items where "ren" is an assignee using the slice_value
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        slice_by: assignee_col_id,
        slice_value: user_ren.login,
        group_value_filters: [MemexProjectColumn::Queryable::FieldValueFilter.new(
          field_object_or_id: status_column.id,
          field_value: "Done",
        )],
        first: 2
      )
      response = query.execute

      # Assert we have the first 2 of 3 "ren" "Done" items.
      # And we still have all the expected slice values and counts, unnaffected by group_value or slice_value.
      assert_equal 3, response.total
      assert_equal expected_slice_values, response.slices&.map { |s| s["slice_value"] }
      assert_equal expected_ren_slice_count, response.slices&.find { |s| s.dig("slice_value") == user_ren.login }&.dig("total_count")
      refute response.primary_groups
      assert_equal items.values_at(3, 5).map(&:id), response.results.map { |r| r["_id"].to_i }
      assert response.end_cursor
      assert response.has_next_page

      # 4) Fetch the last page of 1 items where "ren" is an assignee using the slice_value
      query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        slice_by: assignee_col_id,
        slice_value: user_ren.login,
        group_value_filters: [MemexProjectColumn::Queryable::FieldValueFilter.new(
          field_object_or_id: status_column.id,
          field_value: "Done",
        )],
        first: 2,
        after: response.end_cursor
      )
      response = query.execute

      # Assert we have the last 1 of 3 "ren" "Done" items.
      # And we still have all the expected slice values and counts, unnaffected by group_value or slice_value.
      assert_equal 3, response.total
      assert_equal expected_slice_values, response.slices&.map { |s| s["slice_value"] }
      assert_equal expected_ren_slice_count, response.slices&.find { |s| s.dig("slice_value") == user_ren.login }&.dig("total_count")
      refute response.primary_groups
      assert_equal items.values_at(7).map(&:id), response.results.map { |r| r["_id"].to_i }
      refute response.has_next_page
    end

    test "returns slices/distinct values only" do
      assignees_column = @memex.memex_project_columns.find(&:assignees?)
      users = [@user, create(:verified_user), create(:verified_user)]
      users[1..]&.each { @repo.add_member(_1) }

      # Somewhat arbitrarily assign users to items, ensuring all assignees are flattened and sorted in the distinct values response.
      @unarchived_items[2].content.assignees = [users[0], users[2]]
      @unarchived_items[3].content.assignees = [users[1]]
      populate_elasticsearch_index!(@unarchived_items)

      response = Search::Queries::MemexProjectItemQuery.distinct_values_query(
        project: @memex,
        viewer: @user,
        field_id: assignees_column.id,
      ).execute

      refute_predicate response.results, :present?
      # We expect slices to be sorted alpha-numerically, so ensure our expected values are sorted also.
      expected_values = users.map(&:login).sort
      # The last member of the slices array is the "missing" value, which we don't use. Note that if we ever stop
      # returning the missing value from Elasticsearch to begin with, this test will need updating.
      actual_values = T.must(response.slices).map { _1["slice_value"] }[..-2]
      assert_equal expected_values, actual_values
    end
  end

  context "#build_response" do
    test "handles incomplete Elasticsearch responses" do
      [
        { "hits" => { "total" => 0 } },
        { "error" => "some error" },
        { "hits" => nil },
      ].each do |es_response|
        query = Search::Queries::MemexProjectItemQuery.new(viewer: @user, project: @memex)
        response = query.build_response(
          Search::Responses::MemexProjectItemResponse,
          es_response,
          {}
        )
        response = T.cast(response, Search::Responses::MemexProjectItemResponse)
        assert_equal 0, response.results.size
        assert_equal 0, response.total
        refute response.has_next_page
        refute response.has_previous_page
      end
    end
  end

  context "sorting" do
    test "sorts number fields ascending" do
      @custom_number_column = @memex.add_user_defined_column(
        name: "Custom Number",
        data_type: MemexProjectColumn::Number.data_type,
        position: @memex.columns.count + 1,
        creator: @user,
      )

      sample_number_values_unsorted = [1, 10, 5, 100, 20]
      sample_number_values_sorted = [1, 5, 10, 20, 100]

      sample_number_values_unsorted.each_with_index do |value, idx|
        @unarchived_items[idx].set_column_value(@custom_number_column, value, @user)
      end
      populate_elasticsearch_index!(@unarchived_items)

      unsorted_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
      )
      unsorted_response_values = unsorted_query.execute.results.map do |i|
        i["sort"].first.to_i
      end
      refute_equal sample_number_values_sorted, unsorted_response_values

      sorted_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [@custom_number_column.to_field.sort_fragment(direction: "asc")]
      )
      sorted_response_values = sorted_query.execute.results.map do |i|
        i["sort"].first.to_i
      end
      assert_equal sample_number_values_sorted, sorted_response_values
    end

    test "sorts linked pull request fields in ascending order" do
      linked_pull_requests_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME)

      pull_requests = [
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
        create(:pull_request, :disable_disk_access, repository: @repo, user: @user, head_ref: "ref-#{SecureRandom.hex(6)}"),
      ]

      # 2 items have the first PR
      linked_pr_items_1 = @unarchived_items.values_at(0, 2).map do |item|
        create(:close_issue_reference, issue: item.issue, pull_request: pull_requests[0])
        item
      end

      # 2 items have the second PR
      linked_pr_items_2 = @unarchived_items.values_at(1, 3).map do |item|
        create(:close_issue_reference, issue: item.issue, pull_request: pull_requests[1])
        item
      end

      # 1 item has both the first and second PR. Note that we assign the pull request with the larger number first so
      # that we can validate that it actually sorts by the PR number, not by creation order.
      create(:close_issue_reference, issue: @unarchived_items[-1].issue, pull_request: pull_requests[1])
      create(:close_issue_reference, issue: @unarchived_items[-1].issue, pull_request: pull_requests[0])

      # Provide explicit numbers so that the sort order is deterministic
      pull_requests[0].issue.update(number: 100)
      pull_requests[1].issue.update(number: 1)

      expected_results_unsorted = [4, 3, 2, 1, 0]
      expected_results_sorted_asc = [1, 1, 1, 100, 100]
      # Note that sorting desc applies both within and across items. In other words, an item with 2 PRs will be sorted
      # by its largest PR number when sorting desc and by its smallest PR number when sorting asc. You can see that
      # difference here in the expected results. Our 1 item that 2 linked PRs will sort by 1 when sorting asc and by
      # 100 when sorting desc.
      expected_results_sorted_desc = [100, 100, 100, 1, 1]

      populate_elasticsearch_index!(@unarchived_items)

      # Validate that unsorted state is as expected
      unsorted_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
      )
      unsorted_response_values = unsorted_query.execute.results.map do |i|
        i["sort"].first.to_i
      end
      assert_equal expected_results_unsorted, unsorted_response_values

      # Test sort ascending
      sorted_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [linked_pull_requests_column.to_field.sort_fragment(direction: "asc")]
      )
      sorted_response_values = sorted_query.execute.results.map do |i|
        i["sort"].first.to_i
      end
      assert_equal expected_results_sorted_asc, sorted_response_values

      # Test sort descending
      sorted_query_desc = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [linked_pull_requests_column.to_field.sort_fragment(direction: "desc")]
      )
      sorted_response_values_desc = sorted_query_desc.execute.results.map do |i|
        i["sort"].first.to_i
      end
      assert_equal expected_results_sorted_desc, sorted_response_values_desc
    end

    test "sorts number fields descending" do
      @custom_number_column = @memex.add_user_defined_column(
        name: "Custom Number",
        data_type: MemexProjectColumn::Number.data_type,
        position: @memex.columns.count + 1,
        creator: @user,
      )

      sample_number_values_unsorted = [1, 10, 5, 100, 20]
      sample_number_values_sorted = [100, 20, 10, 5, 1]

      sample_number_values_unsorted.each_with_index do |value, idx|
        @unarchived_items[idx].set_column_value(@custom_number_column, value, @user)
      end
      populate_elasticsearch_index!(@unarchived_items)

      sorted_query = Search::Queries::MemexProjectItemQuery.new(
        project: @memex,
        viewer: @user,
        query: "",
        sort: [@custom_number_column.to_field.sort_fragment(direction: "desc")]
      )
      sorted_response_values = sorted_query.execute.results.map do |i|
        i["sort"].first.to_i
      end
      assert_equal sample_number_values_sorted, sorted_response_values
    end
  end

  context "project_item_owner_ids and redactions" do
    test "returns expected item owner ids, item counts, and slice counts, with or without redactions, exercising global aggregations", es_8_only: true do
      private_repo_admin = create(:user)
      private_repo = create(:private_repository, owner: private_repo_admin)
      another_org_repo = create(:private_repository, :org_owned)
      public_repo = create(:public_repository)

      user_ren = create(:verified_user, login: "ren")
      user_stimpy = create(:verified_user, login: "stimpy")
      user_drafter = create(:verified_user, login: "drafter")
      private_repo.add_member(user_stimpy)
      another_org_repo.add_member(user_stimpy)
      public_repo.add_member(user_ren)
      @repo.add_member(user_ren)
      @repo.add_member(user_stimpy)

      assignee_col_id = @memex.columns.find(&:assignees?)&.id

      items = Array[create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)] #0
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: another_org_repo), memex_project: @memex) #1 - redacted another_org_repo
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: private_repo), memex_project: @memex) #2 - redacted private_repo
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #3
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: @repo), memex_project: @memex) #4
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren, user_stimpy], repository: @repo), memex_project: @memex) #5
      items << create(:memex_project_item, content: create(:issue, assignees: [user_stimpy], repository: @repo), memex_project: @memex) #6
      items << create(:memex_project_item, content: create(:draft_issue).tap { |d| d.update!(assignees: [user_drafter]) }, memex_project: @memex) #7 - draft issue
      items << create(:memex_project_item, content: create(:issue, assignees: [user_ren], repository: public_repo), memex_project: @memex) #8 - public_repo

      populate_elasticsearch_index!(items)

      # Regardless of redactions or the query filtering, we always return the same array of project item owner ids.
      # We also always query the MySQL Repository table only once for redactions and owner ids.
      expected_project_item_owner_ids = [@repo, private_repo, another_org_repo, public_repo].map { |r| r.owner.id }
      query_count = 0

      # Loop through tests with and without include_project_item_owner_ids
      [false, true].each do |include_project_item_owner_ids|
        failure_message = "Test failed with include_project_item_owner_ids=#{include_project_item_owner_ids}"

        # 1) Query with redacted items assigned to user_stimpy
        response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
        assert_max_query_count_per_table({ repositories: 1 }) do
          query = Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            include_project_item_owner_ids:,
          )
          response = query.execute
        end

        # Two Elasticsearch query executions were made since redactions were required user_stimpy items
        assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length, failure_message
        assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
        assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
        assert_equal 7, response&.total, failure_message

        # 2) Query without redacted items by filtering out items assigned to user_stimpy
        response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
        assert_max_query_count_per_table({ repositories: 1 }) do
          query = Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            query: "-assignee:#{user_stimpy.login}",
            include_project_item_owner_ids:,
          )
          response = query.execute
        end

        # Only one Elasticsearch query execution was made since we avoided redactions by filtering out user_stimpy items
        assert_equal query_count += 1, GitHub.dogstats.increments("search.query.total").length
        assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
        assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
        assert_equal 5, response&.total, failure_message

        # 3) Query with redacted items by filtering on items assigned to user_stimpy (some are redacted)
        response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
        assert_max_query_count_per_table({ repositories: 1 }) do
          query = Search::Queries::MemexProjectItemQuery.new(
            project: @memex,
            viewer: @user,
            query: "assignee:#{user_stimpy.login}",
            include_project_item_owner_ids:,
          )
          response = query.execute
        end

        # Two Elasticsearch query executions were made since some user_stimpy items are redacted
        assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length
        assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
        assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
        assert_equal 2, response&.total, failure_message

        # Loop through tests with and without include_empty_slices (nested within loop for with or without include_project_item_owner_ids)
        [false, true].each do |include_empty_slices|
          failure_message = "Test failed with include_project_item_owner_ids=#{include_project_item_owner_ids} and include_empty_slices=#{include_empty_slices}"

          # 4) Slice on Assignees, with no slice_value (requires redactions)
          response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
          assert_max_query_count_per_table({ repositories: 1 }) do
            query = Search::Queries::MemexProjectItemQuery.new(
              project: @memex,
              viewer: @user,
              include_project_item_owner_ids:,
              slice_by: assignee_col_id,
              include_empty_slices:,
            )
            response = query.execute
          end

          # No filtering, so all slices have non-zero values
          expected_slice_values = [user_drafter.login, user_ren.login, user_stimpy.login, MISSING_VALUE_GROUP_KEY]
          expected_sorted_slice_counts = [1, 4, 2, 1]

          # Two Elasticsearch query executions were made since redactions were required for user_stimpy slice counts
          assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length, failure_message
          assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
          assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
          assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }, failure_message
          assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }, failure_message
          assert_equal 7, response&.total, failure_message

          # 5) Slice on Assignees, with a slice_value of user_stimpy (requires redactions)
          response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
          assert_max_query_count_per_table({ repositories: 1 }) do
            query = Search::Queries::MemexProjectItemQuery.new(
              project: @memex,
              viewer: @user,
              include_project_item_owner_ids:,
              slice_by: assignee_col_id,
              slice_value: user_stimpy.login,
              include_empty_slices:,
            )
            response = query.execute
          end

          # Two Elasticsearch query executions were made since redactions were required for user_stimpy slice counts
          assert_equal query_count += 2, GitHub.dogstats.increments("search.query.total").length, failure_message
          assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
          assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
          assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }, failure_message
          assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }, failure_message
          assert_equal 2, response&.total, failure_message

          # 6) Slice on Assignees, with a slice_value of user_stimpy, filtered on visible @repo (redactions if include_empty_slices)
          rresponse = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
          assert_max_query_count_per_table({ repositories: 1 }) do
            query = Search::Queries::MemexProjectItemQuery.new(
              project: @memex,
              viewer: @user,
              query: "#{@repo.owner.name}/#{@repo.name}",
              include_project_item_owner_ids:,
              slice_by: assignee_col_id,
              slice_value: user_stimpy.login,
              include_empty_slices:,
            )
            response = query.execute
          end

          # Filtering on the visible repo, so now the draft issue becomes an empty slice
          expected_slice_values = [user_ren.login, user_stimpy.login, MISSING_VALUE_GROUP_KEY]
          expected_sorted_slice_counts = [3, 2, 1]
          if include_empty_slices
            expected_slice_values << user_drafter.login
            expected_sorted_slice_counts << 0
          end

          # Redactions required only if include_empty_slices
          expected_es_queries = include_empty_slices ? 2 : 1
          assert_equal query_count += expected_es_queries, GitHub.dogstats.increments("search.query.total").length, failure_message
          assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
          assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
          assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }, failure_message
          assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }, failure_message
          assert_equal 2, response&.total, failure_message

          # 7) Slice on Assignees, with a slice_value of user_ren, filtered on visible @repo (redactions if include_empty_slices)
          response = T.let(nil, T.any(T.nilable(Search::Responses::MemexProjectItemResponse), T.nilable(Search::Responses::GroupedMemexProjectItemResponse)))
          assert_max_query_count_per_table({ repositories: 1 }) do
            query = Search::Queries::MemexProjectItemQuery.new(
              project: @memex,
              viewer: @user,
              query: "#{@repo.owner.name}/#{@repo.name}",
              include_project_item_owner_ids:,
              slice_by: assignee_col_id,
              slice_value: user_ren.login,
              include_empty_slices:,
            )
            response = query.execute
          end

          # Redactions required only if include_empty_slices
          expected_es_queries = include_empty_slices ? 2 : 1
          assert_equal query_count += expected_es_queries, GitHub.dogstats.increments("search.query.total").length, failure_message
          assert_same_elements expected_project_item_owner_ids, response&.project_item_owner_ids, failure_message if include_project_item_owner_ids
          assert_nil response&.project_item_owner_ids, failure_message unless include_project_item_owner_ids
          assert_equal expected_slice_values, response&.slices&.map { |s| s["slice_value"] }, failure_message
          assert_equal expected_sorted_slice_counts, response&.slices&.map { |s| s["total_count"] }, failure_message
          assert_equal 3, response&.total, failure_message
        end
      end
    end
  end

  test "excludes _noValue group when there are multiple additionals groups", es_8_only: true do
    status_column = @memex.status_column
    todo_option_id = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
    done_option_id = status_column.settings["options"].find { |o| o["name"] == "Done" }["id"]
    progress_option_id = status_column.settings["options"].find { |o| o["name"] == "In Progress" }["id"]
    assert @unarchived_items.size > 3
    @unarchived_items[0].set_column_value(status_column, todo_option_id, @user)
    @unarchived_items[1].set_column_value(status_column, done_option_id, @user)
    @unarchived_items[2].set_column_value(status_column, progress_option_id, @user)

    populate_elasticsearch_index!(@unarchived_items)

    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      grouping_options: MemexProjectColumn::Groupable::Options.new(
        field_object_or_id: status_column.id,
        groups_page_size: 2
      ),
    )
    response = query.execute
    assert response.has_next_page
    assert_nil T.must(response.primary_groups).nodes.find { |g| g.group_value == MISSING_VALUE_GROUP_KEY }

    # Both aggregations included in total
    assert_equal @unarchived_items.size, response.total

    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      grouping_options: MemexProjectColumn::Groupable::Options.new(
        field_object_or_id: status_column.id,
        groups_page_size: 2,
        cursor: response.end_cursor
      ),
    )
    response = query.execute
    refute response.has_next_page
    refute_nil T.must(response.primary_groups).nodes.find { |g| g.group_value == MISSING_VALUE_GROUP_KEY }
  end

  test "marks has_next_page true when _noValue is the only remaining group", es_8_only: true do
    text_field = create(:memex_project_column, data_type: :text, memex_project: @memex).to_field
    @unarchived_items[0].set_column_value(text_field, "Text", @user)

    populate_elasticsearch_index!(@unarchived_items)

    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      grouping_options: MemexProjectColumn::Groupable::Options.new(
        field_object_or_id: text_field.id,
        groups_page_size: 1
      ),
    )
    response = query.execute
    assert response.has_next_page
    assert_nil T.must(response.primary_groups).nodes.find { |g| g.group_value == MISSING_VALUE_GROUP_KEY }

    query = Search::Queries::MemexProjectItemQuery.new(
      project: @memex.reload,
      viewer: @user,
      grouping_options: MemexProjectColumn::Groupable::Options.new(
        field_object_or_id: text_field.id,
        groups_page_size: 1,
        cursor: response.end_cursor,
      ),
    )
    response = query.execute
    refute response.has_next_page
    refute_nil T.must(response.primary_groups).nodes.find { |g| g.group_value == MISSING_VALUE_GROUP_KEY }
  end

  # Sets multiple column values when requested as an array of [column, value] pairs.
  sig { params(item: MemexProjectItem, column_value_pairs: T::Array[T::Array[T.untyped]]).returns(T.untyped) }
  private def set_column_values(item, column_value_pairs)
    column_value_pairs.each do |pair|
      item.set_column_value(pair[0], pair[1], @user)
    end
  end

  sig { params(field: MemexProjectColumn::Field, document: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
  private def field_value(field, document)
    document.dig("_source", "field_values").find { |f| f["field_id"] == field.id }&.fetch(field.class.value_name.to_s)
  end

  sig { params(item: MemexProjectItem, value: T.untyped, field: MemexProjectColumn::Field).returns(GitHub::StreamProcessors::Message) }
  private def value_create_message(item, value, field)
    build_message(
      {
        actor: Hydro::EntitySerializer.user(@user),
        project: Hydro::EntitySerializer.memex_project(@memex),
        project_column: Hydro::EntitySerializer.memex_project_column(field),
        project_item: Hydro::EntitySerializer.memex_project_item(item),
        value: value,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      },
      schema: "github.memex.v0.MemexProjectColumnValueCreate"
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  private def create_items_with_status_and_priority_columns
    option_names = T.let(%w[Urgent Normal Meh], T::Array[T.nilable(String)])
    priority_column = create(
      :single_select_memex_column,
      memex_project: @memex,
      settings: { options: option_names.map { |name| { name: name, color: "GRAY" } } }
    )

    priority_options = priority_column.settings["options"]
    urgent = priority_options[0]["id"]
    normal = priority_options[1]["id"]
    meh = priority_options[2]["id"]

    status_column = @memex.status_column
    status_options = status_column.settings["options"]
    todo = status_options.find { |o| o["name"] == "Todo" }["id"]
    in_progress = status_options.find { |o| o["name"] == "In Progress" }["id"]
    done = status_options.find { |o| o["name"] == "Done" }["id"]

    items = create_list(:memex_project_item, 1, memex_project: @memex) # no status or priority value
    [todo, in_progress, done].each do |status_id|
      [urgent, normal, meh].each do |priority_id|
        item = create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
        set_column_values(item, [[status_column, status_id], [priority_column, priority_id]])
        items << item
      end
      # no priority value
      item = create(:memex_project_item, content: create(:issue, repository: @repo), memex_project: @memex)
      set_column_values(item, [[status_column, status_id]])
      items << item
    end
    { items:, status_column:, priority_column: }
  end
end
