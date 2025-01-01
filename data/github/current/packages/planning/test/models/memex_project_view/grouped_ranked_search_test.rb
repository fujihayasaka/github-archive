# typed: true
# frozen_string_literal: true

require "test_helper"

class GroupedRankedSearchTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @user       = create(:user)
    @org        = create(:organization, admin: @user)
    @other_user = create(:verified_user).tap { |u| @org.add_member(u) }
    @memex      = create(:memex_project, owner: @org)
    @memex_view = @memex.default_view

    @text_column   = create(:memex_project_column, user_defined: true, data_type: :text, memex_project: @memex)
    @number_column = create(:memex_project_column, user_defined: true, data_type: :number, memex_project: @memex)
    @date_column   = create(:memex_project_column, user_defined: true, data_type: :date, memex_project: @memex)

    @iteration_column = create(:iteration_memex_column_with_completed_iterations, memex_project: @memex, upcoming: 2, completed: 1)
    @status_column, @todo_option, @in_progress_option, @done_option = load_status_column_with_options

    @item_1 = create_item(
      text: "foo",
      number: 1,
      status: @done_option,
      iteration: @iteration_column.settings_all_iterations.first["id"]
    )

    @item_2 = create_item(
      text: "foo",
      number: 2,
      status: @todo_option,
      iteration: @iteration_column.settings_all_iterations.third["id"],
      date: "2020-12-31"
    )

    @item_3 = create_item(
      text: "foo",
      status: @in_progress_option,
      iteration: @iteration_column.settings_all_iterations.second["id"],
      date: "2020-01-01"
    )

    @item_4 = create_item
  end

  setup do
    @sort_by  = { column: @number_column, direction: "asc" }
    @group_by = [@text_column.id]

    @memex_view.update!(
      filter: "-#{@status_column.name_slug}:foobar123",
      group_by: @group_by,
      sort_by: [[@sort_by[:column].id, @sort_by[:direction]]]
    )

    @grs = create_grs(group_by: @text_column, sort_by: @sort_by)
  end

  context "#group_items" do
    test "groups items under nil group if column isn't provided" do
      grs      = create_grs(group_by: nil)
      groups   = grs.group_items
      expected = { group(column: nil) => [@item_1, @item_2, @item_3, @item_4] }

      assert_hash_ordering(expected, groups)
    end

    test "groups items by values on given column" do
      groups = @grs.group_items

      expected = {
        group(column: @text_column, value: "foo") => [@item_1, @item_2, @item_3],
        group(column: @text_column, value: "") => [@item_4]
      }

      assert_hash_ordering(expected, groups)
    end
  end

  context "#sort_groups" do
    test "groups remain in alphabetical order for generic types" do
      item          = create_item(text: "bar")
      grs           = create_grs(group_by: @text_column)
      groups        = grs.group_items
      sorted_groups = grs.sort_groups(groups)

      expected = {
        group(column: @text_column, value: "bar") => [item],
        group(column: @text_column, value: "foo") => [@item_1, @item_2, @item_3],
        group(column: @text_column, value: "") => [@item_4]
      }

      assert_equal expected.keys, sorted_groups.keys
    end

    test "groups remain in user-defined order for single select" do
      grs           = create_grs(group_by: @status_column)
      groups        = grs.group_items
      sorted_groups = grs.sort_groups(groups)

      expected = {
        group(column: @status_column, value: @todo_option) => [@item_2],
        group(column: @status_column, value: @in_progress_option) => [@item_3],
        group(column: @status_column, value: @done_option) => [@item_1],
        group(column: @status_column) => [@item_4]
      }

      assert_hash_ordering(expected, sorted_groups)
    end

    test "groups remain in user-defined order for iterations" do
      grs           = create_grs(group_by: @iteration_column)
      groups        = grs.group_items
      sorted_groups = grs.sort_groups(groups)

      iteration0_id = @iteration_column.settings_all_iterations_ids(["Iteration -1"]).first
      iteration1_id = @iteration_column.settings_all_iterations_ids(["Iteration 1"]).first
      iteration2_id = @iteration_column.settings_all_iterations_ids(["Iteration 2"]).first

      expected = {
        group(column: @iteration_column, value: iteration0_id) => [@item_1],
        group(column: @iteration_column, value: iteration1_id) => [@item_3],
        group(column: @iteration_column, value: iteration2_id) => [@item_2],
        group(column: @iteration_column) => [@item_4]
      }

      assert_hash_ordering(expected, sorted_groups)
    end

    test "groups remain in date-defined order for dates" do
      grs           = create_grs(group_by: @date_column)
      groups        = grs.group_items
      sorted_groups = grs.sort_groups(groups)

      expected = {
        group(column: @date_column, value: Date.parse("2020-01-01")) => [@item_3],
        group(column: @date_column, value: Date.parse("2020-12-31")) => [@item_2],
        group(column: @date_column) => [@item_1, @item_4]
      }

      assert_hash_ordering(expected, sorted_groups)
    end
  end

  context "#sort_grouped_items" do
    test "returns grouped items as-is if sort by column isn't provided" do
      grs           = create_grs(group_by: @text_column, sort_by: nil)
      groups        = grs.group_items
      sorted_groups = grs.sort_grouped_items(groups)

      assert_hash_ordering(groups, sorted_groups)
    end

    test "sorts grouped items by given column in ascending direction" do
      grs           = create_grs(group_by: @text_column, sort_by: { column: @date_column, direction: "asc" })
      groups        = grs.group_items
      sorted_groups = grs.sort_grouped_items(groups)

      # nil items should remain at the end of the list
      expected = {
        group(column: @text_column, value: "foo") => [@item_3, @item_2, @item_1],
        group(column: @text_column, value: "") => [@item_4]
      }

      assert_hash_ordering(expected, sorted_groups)
    end

    test "sorts grouped items by given column in descending direction" do
      grs           = create_grs(group_by: @text_column, sort_by: { column: @date_column, direction: "desc" })
      groups        = grs.group_items
      sorted_groups = grs.sort_grouped_items(groups)

      # nil items should remain at the end of the list
      expected = {
        group(column: @text_column, value: "foo") => [@item_2, @item_3, @item_1],
        group(column: @text_column, value: "") => [@item_4]
      }

      assert_hash_ordering(expected, sorted_groups)
    end

    test "sorts grouped items by multiple columns in different directions and assigns sort_values from those columns" do
      grs = create_grs(
        group_by: @text_column,
        sort_by: [
          { column: @iteration_column, direction: "desc" },
          { column: @text_column, direction: "asc" },
          { column: @number_column, direction: "desc" },
          { column: @date_column, direction: "asc" },
          { column: @status_column, direction: "desc" }
        ]
      )

      groups = grs.group_items
      sorted_groups = grs.sort_grouped_items(groups)

      # nil items should remain at the end of the list
      expected = {
        group(column: @text_column, value: "foo") => [@item_2, @item_3, @item_1],
        group(column: @text_column, value: "") => [@item_4]
      }

      expected.values.flatten.each { |item| assert_nil item.sort_values }

      assert_hash_ordering expected, sorted_groups,
        "Expected #{expected.values.flatten.pluck(:id)} got #{sorted_groups.values.flatten.pluck(:id)}"

      sorted_groups.values.flatten.each { |item| refute_nil item.sort_values }
    end
  end

  context "#rank_grouped_items" do
    test "applies ranks to items after sorting" do
      grs          = create_grs(group_by: @text_column, sort_by: { column: @text_column, direction: "asc" })
      groups       = grs.group_items
      sorted_items = grs.sort_grouped_items(groups)
      ranked_items = grs.rank_grouped_items(sorted_items)

      expected = {
        group(column: @text_column, value: "foo") => [
          { item: @item_1, ranking: 1 },
          { item: @item_2, ranking: 2 },
          { item: @item_3, ranking: 3 }
        ],
        group(column: @text_column, value: "") => [{ item: @item_4.reload, ranking: 4 }]
      }

      assert_hash_ordering(expected, ranked_items)
    end
  end

  context "#execute" do
    test "groups, sorts, filters and returns ranked items in correct format" do
      @memex_view.update!(filter: "-status:\"In Progress\"")

      grs = create_grs(group_by: @number_column, sort_by: { column: @text_column, direction: "asc" })

      expected = {
        group(column: @number_column, value: 1) => [{ item: @item_1, ranking: 1 }],
        group(column: @number_column, value: 2) => [{ item: @item_2, ranking: 2 }],
        group(column: @number_column) => [{ item: @item_4, ranking: 4 }]
      }

      assert_hash_ordering(expected, grs.execute)
    end

    test "reverses groups if sorted/grouped by same column and direction descending" do
      grs = create_grs(group_by: @number_column, sort_by: { column: @number_column, direction: "desc" })

      expected = {
        group(column: @number_column) => [{ item: @item_3, ranking: 3 }, { item: @item_4, ranking: 4 }],
        group(column: @number_column, value: 2) => [{ item: @item_2, ranking: 2 }],
        group(column: @number_column, value: 1) => [{ item: @item_1, ranking: 1 }]
      }

      assert_hash_ordering(expected, grs.execute)
    end

    test "items that the user cannot view are redacted if use_redactor is true" do
      memex          = create(:memex_project, owner: @org)
      view           = memex.default_view
      private_repo   = create(:private_repository, owner: @other_user)
      private_issue  = create(:issue, repository: private_repo)
      private_item   = create_item(memex:, text: "private", content: private_issue, owner: @other_user)
      redacted_group = group(view:)

      # check that the current viewer cannot see the private issue
      redacted_items = create_grs(memex:, view:, use_redactor: true).execute

      assert_equal 1, redacted_items.length
      assert redacted_items[redacted_group].present?
      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, redacted_items[redacted_group].first[:item].content_type

      # check that the owner can see the private issue
      private_group = group(column: @text_column, value: "private")

      unredacted_items = create_grs(memex:, viewer: @other_user, group_by: @text_column).execute

      assert_equal 1, unredacted_items.length
      assert unredacted_items[private_group].present?
      assert_equal "Issue", unredacted_items[private_group].first[:item].content_type
      assert_equal private_item, unredacted_items[private_group].first[:item]
    end

    test "items that the user cannot view are not redacted if use_redactor is false" do
      memex         = create(:memex_project, owner: @org)
      private_repo  = create(:private_repository, owner: @other_user)
      private_issue = create(:issue, repository: private_repo)
      private_item  = create_item(memex: memex, text: "private", content: private_issue, owner: @other_user)

      # check that the item is still placed under `nil` group and not "private"
      redacted_items = create_grs(memex: memex, group_by: @text_column, use_redactor: false).execute
      nil_group      = group(column: @text_column)

      assert_equal 1, redacted_items.length
      assert redacted_items[nil_group].present?
      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, redacted_items[nil_group].first[:item].content_type
      assert_equal private_item, redacted_items[nil_group].first[:item]

      # check that the item is placed under "private" group if a user with permissions can see it
      private_group = group(column: @text_column, value: "private")

      items = create_grs(memex: memex, viewer: @other_user, group_by: @text_column, use_redactor: false).execute

      assert_equal 1, items.length
      assert items[private_group].present?
      refute_equal MemexProjectItem::REDACTED_ITEM_TYPE, items[private_group].first[:item].content_type
      assert_equal private_item, items[private_group].first[:item]
    end
  end

  context "#groups" do
    test "returns groups in the correct ordering when ascending order" do
      create_item(text: "baz")
      create_item(text: "bar")

      grs = create_grs(group_by: @text_column, sort_by: { column: @text_column, direction: "asc" })

      expected = [
        group(column: @text_column, value: "bar"),
        group(column: @text_column, value: "baz"),
        group(column: @text_column, value: "foo"),
        group(column: @text_column, value: "")
      ]

      assert_hash_ordering(expected, grs.groups)
    end

    test "returns groups in the correct ordering when descending order" do
      create_item(text: "baz")
      create_item(text: "bar")

      grs = create_grs(group_by: @text_column, sort_by: { column: @text_column, direction: "desc" })

      expected = [
        group(column: @text_column, value: ""),
        group(column: @text_column, value: "foo"),
        group(column: @text_column, value: "baz"),
        group(column: @text_column, value: "bar")
      ]

      assert_hash_ordering(expected, grs.groups)
    end

    test "returns group as nil if it only contains redacted items" do
      memex         = create(:memex_project, owner: @org)
      private_repo  = create(:private_repository, owner: @other_user)
      private_issue = create(:issue, repository: private_repo)
      private_item  = create_item(memex: memex, text: "private", content: private_issue, owner: @other_user)

      [nil, "foo", "bar", "baz"].each do |text|
        create_item(memex: memex, text: text)
      end

      grs = create_grs(memex: memex, group_by: @text_column)

      expected = [
        group(column: @text_column, value: "bar"),
        group(column: @text_column, value: "baz"),
        group(column: @text_column, value: "foo"),
        group(column: @text_column, value: "")
      ]

      assert_equal expected, grs.groups
    end

    test "returns group if at least one item is not redacted" do
      memex         = create(:memex_project, owner: @org)
      private_repo  = create(:private_repository, owner: @other_user)
      private_issue = create(:issue, repository: private_repo)
      private_item  = create_item(memex: memex, text: "foo", content: private_issue, owner: @other_user)

      create_item(memex: memex, text: "foo")
      grs = create_grs(memex: memex, group_by: @text_column)

      expected = [
        group(column: @text_column, value: "foo"),
        group(column: @text_column, value: "")
      ]

      assert_equal expected, grs.groups
    end

    test "returns an array containing nil if no groups exist" do
      memex    = create(:memex_project, owner: @org)
      item     = create_item(memex: memex)
      grs      = create_grs(memex: memex, group_by: @text_column)
      expected = [group(column: @text_column, value: "")]

      assert_equal expected, grs.groups
    end
  end

  if GitHub.enterprise?
    test "it does not log for enterprise" do
      stats = GitHub::MemoryDogstatsD.new

      GitHub.stubs(:dogstats).returns(stats)

      subject = create_grs(
        memex: @memex,
        group_by: @text_column,
        sort_by: {
          direction: "desc",
          column: @text_column
        }
      )

      subject.execute

      assert_empty stats.distributions("platform.memex.grouped_ranked_search.prefill_associations!_in_ms")
      assert_empty stats.distributions("platform.memex.grouped_ranked_search.group_items_in_ms")
      assert_empty stats.distributions("platform.memex.grouped_ranked_search.sort_groups_in_ms")
      assert_empty stats.distributions("platform.memex.grouped_ranked_search.sort_grouped_items_in_ms")
      assert_empty stats.distributions("platform.memex.grouped_ranked_search.rank_grouped_items_in_ms")
      assert_empty stats.distributions("platform.memex.grouped_ranked_search.reverse_groups_in_ms")
      assert_empty stats.distributions("platform.memex.grouped_ranked_search.filter_ranked_items_in_ms")
      assert_empty stats.distributions("platform.memex.grouped_ranked_search.total_in_ms")
    end
  else
    context "logging metrics" do
      test "it logs when user feature flag is enabled" do
        stats = GitHub::MemoryDogstatsD.new

        GitHub.stubs(:dogstats).returns(stats)

        enable_feature_flag(:memex_grouped_ranked_search_measurements, @user)

        subject = create_grs(
          memex: @memex,
          group_by: @text_column,
          sort_by: {
            direction: "desc",
            column: @text_column
          }
        )

        subject.execute

        assert_equal 1, stats.distributions("platform.memex.grouped_ranked_search.prefill_associations!_in_ms").length
        assert_equal 1, stats.distributions("platform.memex.grouped_ranked_search.group_items_in_ms").length
        assert_equal 1, stats.distributions("platform.memex.grouped_ranked_search.sort_groups_in_ms").length
        assert_equal 1, stats.distributions("platform.memex.grouped_ranked_search.sort_grouped_items_in_ms").length
        assert_equal 1, stats.distributions("platform.memex.grouped_ranked_search.rank_grouped_items_in_ms").length
        assert_equal 1, stats.distributions("platform.memex.grouped_ranked_search.reverse_groups_in_ms").length
        assert_equal 1, stats.distributions("platform.memex.grouped_ranked_search.filter_ranked_items_in_ms").length
        assert_equal 1, stats.distributions("platform.memex.grouped_ranked_search.total_in_ms").length
      end

      test "it does not log when user feature flag is disabled" do
        stats = GitHub::MemoryDogstatsD.new

        GitHub.stubs(:dogstats).returns(stats)

        disable_feature_flag(:memex_grouped_ranked_search_measurements)

        subject = create_grs(
          memex: @memex,
          group_by: @text_column,
          sort_by: {
            direction: "desc",
            column: @text_column
          }
        )

        subject.execute

        assert_empty stats.distributions("platform.memex.grouped_ranked_search.prefill_associations!_in_ms")
        assert_empty stats.distributions("platform.memex.grouped_ranked_search.group_items_in_ms")
        assert_empty stats.distributions("platform.memex.grouped_ranked_search.sort_groups_in_ms")
        assert_empty stats.distributions("platform.memex.grouped_ranked_search.sort_grouped_items_in_ms")
        assert_empty stats.distributions("platform.memex.grouped_ranked_search.rank_grouped_items_in_ms")
        assert_empty stats.distributions("platform.memex.grouped_ranked_search.reverse_groups_in_ms")
        assert_empty stats.distributions("platform.memex.grouped_ranked_search.filter_ranked_items_in_ms")
        assert_empty stats.distributions("platform.memex.grouped_ranked_search.total_in_ms")
      end
    end
  end

  def load_status_column_with_options
    status_column         = @memex.status_column
    todo_option_id        = status_column.settings["options"].find { |o| o["name"] == "Todo" }["id"]
    in_progress_option_id = status_column.settings["options"].find { |o| o["name"] == "In Progress" }["id"]
    done_option_id        = status_column.settings["options"].find { |o| o["name"] == "Done" }["id"]

    [status_column, todo_option_id, in_progress_option_id, done_option_id]
  end

  def create_grs(memex: @memex, viewer: @user, group_by: nil, sort_by: nil, use_redactor: true, view: @memex_view)
    memex.reload

    MemexProjectView::GroupedRankedSearch.new(
      memex:,
      view:,
      filter: memex.default_view.filter,
      columns: memex.memex_project_columns,
      items: memex.memex_project_items,
      viewer:,
      group_by:,
      sort_by:,
      use_redactor:
    ).tap do |grs|
      grs.send(:prefill_associations!)
    end
  end

  def create_item(memex: @memex, text: nil, number: nil, status: nil, date: nil, iteration: nil, content: create(:issue), owner: @user)
    create(:memex_project_item, memex_project: memex, content:).tap do |item|
      item.set_column_value(@text_column, text, owner)
      item.set_column_value(@number_column, number, owner)
      item.set_column_value(@status_column, status, owner)
      item.set_column_value(@iteration_column, iteration, owner)
      item.set_column_value(@date_column, date, owner)

      RebalanceMemexProjectJob.perform_now(memex.id, nil)
      item.reload
    end
  end

  def assert_hash_ordering(expected, result, message = nil)
    assert_equal expected.to_a, result.to_a, message
  end

  # Syntactic sugar for creating groups so we don't have to keep specifying the verbose name.
  def group(column: nil, view: @memex_view, title: "", value: nil)
    MemexProject::Group.new(column:, title:, value:, view:)
  end
end
