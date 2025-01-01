# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItemCsvSerializerTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @user = create(:verified_user)
    @memex = create(:memex_project, owner: @user)

    @repo = create(:public_repository)
    @issue = create(:issue, repository: @repo)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)

    @private_repo_admin = create(:user)
    @private_repo = create(:private_repository, owner: @private_repo_admin)
    @private_issue = create(:issue, repository: @private_repo, user: @private_repo_admin)
    @private_pull = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @private_repo_admin)

    # Create linked pull requests with varying visibility to test column value redactions
    create(:close_issue_reference, issue: @issue, pull_request: @pull)
    create(:close_issue_reference, issue: @issue, pull_request: @private_pull)
    @memex.default_view.make_column_visible!(@memex.columns.find(&:linked_pull_requests?))
  end

  context "#result" do
    test "contains the CSV header based on the memex project visible columns" do
      issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue)

      visible_columns = @memex.default_view.visible_columns
      csv_headers = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item],
        prefilled_associations: prefill_associations!([issue_item], visible_columns),
      )
      .result
      .csv_headers

      # The CSV headers must include the visible columns and the content URL column
      # as per existing behavior in the client
      assert_equal visible_columns.map(&:name).insert(1, "URL").to_csv, csv_headers
    end

    test "contains the CSV header based on the memex project visible columns from non-denormalized source" do
      issue = create(:issue, repository: @repo)
      issue_item = create(:memex_project_item, memex_project: @memex, content: issue)

      MemexProjectItemPrefiller.new(
        [issue_item],
        columns: @memex.default_view.visible_columns
      ).prefill

      visible_columns = @memex.default_view.visible_columns
      csv_headers = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item],
      )
      .result
      .csv_headers

      # The CSV headers must include the visible columns and the content URL column
      # as per existing behavior in the client
      assert_equal visible_columns.map(&:name).insert(1, "URL").to_csv, csv_headers
    end

    test "serializes a memex item to CSV format" do
      issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue)

      visible_columns = @memex.default_view.visible_columns
      serialized_result = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item],
        prefilled_associations: prefill_associations!([issue_item], visible_columns),
      ).result

      # Issue Item
      csv_assert_match @issue.title, serialized_result.csv_rows
      csv_assert_match @issue.url,   serialized_result.csv_rows
      csv_assert_match @pull.url,    serialized_result.csv_rows
    end

    test "serializes a memex item to CSV format from non-denormalized source" do
      issue = create(:issue, repository: @repo)
      issue_item = create(:memex_project_item, memex_project: @memex, content: issue)

      visible_columns = @memex.default_view.visible_columns

      MemexProjectItemPrefiller.new(
        [issue_item],
        columns: visible_columns
      ).prefill

      serialized_result = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item],
      ).result

      csv_assert_match issue.title, serialized_result.csv_rows
      csv_assert_match issue.url, serialized_result.csv_rows
    end

    test "provides a convenience method returning the entries for a CSV" do
      issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue)
      pull_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @pull)

      visible_columns = @memex.default_view.visible_columns
      serialized_entries = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item, pull_item],
        prefilled_associations: prefill_associations!(
          [issue_item, pull_item],
          visible_columns
        ),
      )
      .result
      .entries

      csv_headers, csv_row_1, csv_row_2 = serialized_entries
      assert_match visible_columns.map(&:name).insert(1, "URL").to_csv, serialized_entries.first

      [@issue.title, @issue.url, @pull.url].each { |expected_value| assert_match expected_value, csv_row_1 }
      [@pull.title, @pull.url].each { |expected_value| assert_match expected_value, csv_row_2 }
    end

    test "reads the text value of the field" do
      issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue)

      column = create(:memex_project_column, user_defined: true, data_type: :text, memex_project: @memex, name: "Text")
      column_value = create(
        :memex_project_column_value,
        value: "foo",
        json_value: { raw: "bar", html: "buck" },
        memex_project_column: column,
        memex_project_item: issue_item,
      )

      @memex.default_view.make_column_visible!(column)

      serialized_result = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item],
        prefilled_associations: prefill_associations!([issue_item], [column]),
      ).result

      assert_match column.name, serialized_result.csv_headers
      csv_assert_match column_value.value, serialized_result.csv_rows
    end

    test "reads the text value of the field from non-denormalized source" do
      issue = create(:issue, repository: @repo)
      issue_item = create(:memex_project_item, memex_project: @memex, content: issue)

      column = create(:memex_project_column, user_defined: true, data_type: :text, memex_project: @memex, name: "Text")
      column_value = create(
        :memex_project_column_value,
        value: "foo",
        json_value: { raw: "bar", html: "buck" },
        memex_project_column: column,
        memex_project_item: issue_item,
      )

      @memex.default_view.make_column_visible!(column)

      MemexProjectItemPrefiller.new(
        [issue_item],
        columns: @memex.default_view.visible_columns
      ).prefill

      serialized_result = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item],
      ).result

      assert_match column.name, serialized_result.csv_headers
      csv_assert_match column_value.value, serialized_result.csv_rows
    end

    test "passes its items through the redactor" do
      private_issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @private_issue)

      serialized_items = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [private_issue_item],
        prefilled_associations: prefill_associations!(
          [private_issue_item],
          @memex.default_view.visible_columns
        ),
      )
      .result
      .csv_rows
      .first

      assert_match "You can't see this item", serialized_items
      refute_match @private_issue.title, serialized_items
      refute_match @private_issue.url, serialized_items
    end

    test "passes its items through the redactor from non-denormalized source" do
      private_issue = create(:issue, repository: @private_repo, user: @private_repo_admin)
      private_issue_item = create(:memex_project_item, memex_project: @memex, content: private_issue)

      MemexProjectItemPrefiller.new(
        [private_issue_item],
        columns: @memex.default_view.visible_columns
      ).prefill

      serialized_items = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [private_issue_item],
      )
      .result
      .csv_rows
      .first

      assert_match "You can't see this item", serialized_items
      refute_match private_issue.title, serialized_items
      refute_match private_issue.url, serialized_items
    end

    test "passes linked pull requests through the redactor" do
      issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue)
      serialized_items = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item],
        prefilled_associations: prefill_associations!(
          [issue_item],
          @memex.default_view.visible_columns
        ),
      )
      .result
      .csv_rows
      .first

      # The linked @private_pull has been redacted from issue_item
      refute_match @private_pull.url, serialized_items
      assert_match @pull.url, serialized_items
    end

    test "traces the (internal) csv_serialized_memex_items method" do
      issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue)
      serialized_result = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item],
        prefilled_associations: prefill_associations!(
          [issue_item],
          @memex.default_view.visible_columns
        ),
      ).result

      refute_nil span = find_span_by(name: "memex_project_item_csv_serializer#csv_serialized_memex_items")

      complex_attributes = MemexProjectColumn.data_types.keys + %w[status gh.memex.csv_serializer.width_bucket]

      # Verify simple attributes exactly.
      assert_same_hash(
        {
          "gh.memex.csv_serializer.height" => 1,
          "gh.memex.csv_serializer.height_bucket" => "xs",
          "gh.memex.csv_serializer.width" => @memex.default_view.visible_columns.length,
          "gh.memex.csv_serializer.has_prefilled_associations" => true,
        },
        span.attributes.except(*complex_attributes)
      )

      # Verify that more complex attributes are at least non-nil
      complex_attributes.each do |attribute|
        refute_nil span.attributes[attribute], "expected '#{attribute}' span attribute to be non-nil"
      end
    end

    test "does not log any redactions" do
      issue = create(:issue, repository: @repo, user: @user)
      issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: issue)
      serializer = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item],
        prefilled_associations: prefill_associations!(
          [issue_item],
          @memex.default_view.visible_columns
        )
      )

      refute_logged(Body: MemexProjectItemCsvSerializer::UNEXPECTED_REDACTION_LOG_MESSAGE) do
        result = serializer.result

        # Check that redactions were actually made, even though none were logged
        refute result.csv_rows.any? { |i| i.include?("You can't see this item") }
      end

      assert_dogstats_count_value 0, MemexProjectItemCsvSerializer::UNEXPECTED_REDACTION_METRIC
      assert_dogstats_increment 1, MemexProjectItemCsvSerializer::ZERO_REDACTIONS_METRIC
    end

    test "logs redactions from the legacy item redactor" do
      issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue)
      private_issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @private_issue)

      serializer = MemexProjectItemCsvSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [issue_item, private_issue_item],
        prefilled_associations: prefill_associations!(
          [issue_item, private_issue_item],
          @memex.default_view.visible_columns
        )
      )

      assert_logged(Body: MemexProjectItemCsvSerializer::UNEXPECTED_REDACTION_LOG_MESSAGE) do
        result = serializer.result

        # Check that redactions were actually made
        assert result.csv_rows.any? { |i| i.include?("You can't see this item") }
      end

      assert_dogstats_count_value 1, MemexProjectItemCsvSerializer::UNEXPECTED_REDACTION_METRIC
    end
  end

  private def csv_assert_match(expected, actual)
    assert_match expected, actual.first
  end

  private def prefill_associations!(items, columns)
    prefilled_result = MemexProjectItemPrefiller.new(
      items,
      columns:,
      read_denormalized_title: true,
      title_column: @memex.columns.find(&:title?),
    ).prefill
    refute_nil prefilled_result
    prefilled_result
  end
end
