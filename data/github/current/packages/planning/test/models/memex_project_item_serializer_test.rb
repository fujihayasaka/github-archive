# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItemSerializerTest < GitHub::TestCase
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

    @issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @issue)
    @pull_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @pull)
    @private_issue_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @private_issue)
    @private_pull_item = create(:memex_project_item, :with_denormalized_title, memex_project: @memex, content: @private_pull)

    @items = [@issue_item, @pull_item, @private_issue_item, @private_pull_item]
  end

  context "#result" do
    test "serializes a memex item" do
      MemexProjectItemPrefiller.new(
        [@issue_item],
        columns: @memex.default_view.visible_columns
      ).prefill
      serialized_result = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@issue_item]
      ).result

      serialized_item = serialized_result.items.first
      assert_equal @issue_item.id, serialized_item[:id]
      assert_equal @issue_item.content.id, serialized_item[:contentId]
      assert_equal @issue_item.content_type, serialized_item[:contentType]
      assert_equal @memex.default_view.visible_columns.count, serialized_item[:memexProjectColumnValues].count
    end

    test "serializes a memex item and includes updatedAt" do
      MemexProjectItemPrefiller.new(
        [@issue_item],
        columns: @memex.default_view.visible_columns
      ).prefill
      serialized_result = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@issue_item]
      ).result

      serialized_item = serialized_result.items.first
      assert_equal @issue_item.id, serialized_item[:id]
      assert_equal @issue_item.content.id, serialized_item[:contentId]
      assert_equal @issue_item.content_type, serialized_item[:contentType]
      assert_equal @issue_item.updated_at, serialized_item[:updatedAt]
      assert_equal @memex.default_view.visible_columns.count, serialized_item[:memexProjectColumnValues].count
    end

    test "serializes a memex item when using the prefilled_associations option" do
      prefill_result = MemexProjectItemPrefiller.new(
        [@issue_item],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill
      refute_nil prefill_result

      serialized_result = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@issue_item],
        prefilled_associations: prefill_result
      ).result

      serialized_item = serialized_result.items.first
      assert_equal @issue_item.id, serialized_item[:id]
      assert_equal @issue_item.content.id, serialized_item[:contentId]
      assert_equal @issue_item.content_type, serialized_item[:contentType]
      assert_equal @memex.default_view.visible_columns.count, serialized_item[:memexProjectColumnValues].count
    end

    test "reads the serialized value of the field" do
      column = create(:memex_project_column, user_defined: true, data_type: :text, memex_project: @memex)
      column_value = create(
        :memex_project_column_value,
        value: "foo",
        json_value: { raw: "bar", html: "bar" },
        memex_project_column: column,
        memex_project_item: @issue_item,
      )

      @memex.default_view.make_column_visible!(column)

      MemexProjectItemPrefiller.new([@issue_item], columns: @memex.reload.default_view.visible_columns).prefill
      serialized_result = MemexProjectItemSerializer.new(viewer: @user, memex: @memex, items: [@issue_item]).result

      serialized_item = serialized_result.items.first
      assert_equal @issue_item.id, serialized_item[:id]
      assert_equal @issue_item.content.id, serialized_item[:contentId]
      assert_equal @issue_item.content_type, serialized_item[:contentType]
      assert_equal @memex.default_view.visible_columns.count, serialized_item[:memexProjectColumnValues].count

      serialized_column_value = serialized_item[:memexProjectColumnValues].find { |val| val[:memexProjectColumnId] == column.id }
      assert_equal column_value.json_value, serialized_column_value[:value]
    end

    test "passes its items through the redactor" do
      serialized_result = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@private_issue_item]
      ).result

      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, serialized_result.items.first[:contentType]
    end

    test "passes its items through the redactor when using the prefilled_associations option" do
      prefill_result = MemexProjectItemPrefiller.new(
        [@issue_item],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill
      refute_nil prefill_result

      serialized_result = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@private_issue_item],
        prefilled_associations: prefill_result
      ).result

      assert_equal MemexProjectItem::REDACTED_ITEM_TYPE, serialized_result.items.first[:contentType]
    end

    test "passes linked pull requests through the redactor when omitting the prefilled_associations option (non-denormalized data)" do
      MemexProjectItemPrefiller.new([@issue_item], columns: @memex.default_view.visible_columns).prefill

      serialized_result = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@issue_item]
      ).result

      # The linked @private_pull has been redacted from @issue_item
      linked_prs_column_id =
      linked_pull_request_ids = serialized_result.items.first[:memexProjectColumnValues].find { |c| c[:memexProjectColumnId] == MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME }[:value]
      assert_equal 1, linked_pull_request_ids.count
      assert_equal @pull.id, linked_pull_request_ids.first[:id]
    end

    test "passes linked pull requests through the redactor when using the prefilled_associations option (denormalized data)" do
      prefill_result = MemexProjectItemPrefiller.new(
        [@issue_item],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill
      refute_nil prefill_result

      serialized_result = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@issue_item],
        prefilled_associations: prefill_result
      ).result

      # The linked @private_pull has been redacted from @issue_item
      linked_pull_request_ids = serialized_result.items.first[:memexProjectColumnValues].find { |c| c[:memexProjectColumnId] == MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME }[:value]
      assert_equal 1, linked_pull_request_ids.count
      assert_equal @pull.id, linked_pull_request_ids.first[:id]
    end

    test "traces the (internal) serialized_memex_items method" do
      prefill_result = MemexProjectItemPrefiller.new(
        [@issue_item],
        columns: @memex.default_view.visible_columns,
        read_denormalized_title: true,
        title_column: @memex.columns.find(&:title?)
      ).prefill
      refute_nil prefill_result

      serialized_result = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@issue_item],
        prefilled_associations: prefill_result
      ).result

      refute_nil span = find_span_by(name: "memex_project_item_serializer#serialized_memex_items")

      complex_attributes = MemexProjectColumn.data_types.keys + %w[status gh.memex.serializer.width_bucket]

      # Verify simple attributes exactly.
      assert_same_hash(
        {
          "gh.memex.serializer.height" => 1,
          "gh.memex.serializer.height_bucket" => "xs",
          "gh.memex.serializer.width" => @memex.default_view.visible_columns.length,
          "gh.memex.serializer.has_prefilled_associations" => true,
        },
        span.attributes.except(*complex_attributes)
      )

      # Verify that more complex attributes are at least non-nil
      complex_attributes.each do |attribute|
        refute_nil span.attributes[attribute], "expected '#{attribute}' span attribute to be non-nil"
      end
    end

    test "does not log any redactions by default" do
      MemexProjectItemPrefiller
        .new(
          [@issue_item, @private_issue_item],
          columns: @memex.default_view.visible_columns
        )
        .prefill

      serializer = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@issue_item, @private_issue_item]
      )

      refute_logged(Body: MemexProjectItemSerializer::UNEXPECTED_REDACTION_LOG_MESSAGE) do
        result = serializer.result

        # Check that redactions were actually made, even though none were logged
        assert result.items.any? { |i| i[:contentType] == MemexProjectItem::REDACTED_ITEM_TYPE }
      end

      refute_dogstats_count MemexProjectItemSerializer::UNEXPECTED_REDACTION_METRIC
    end

    test "logs the redactions that were made from a paginated context" do
      MemexProjectItemPrefiller
        .new(
          [@issue_item, @private_issue_item],
          columns: @memex.default_view.visible_columns
        )
        .prefill

      serializer = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@issue_item, @private_issue_item],
        from_paginated_context: true
      )

      assert_logged(Body: MemexProjectItemSerializer::UNEXPECTED_REDACTION_LOG_MESSAGE) do
        result = serializer.result
        assert result.items.any? { |i| i[:contentType] == MemexProjectItem::REDACTED_ITEM_TYPE }
      end

      assert_dogstats_count_value 1, MemexProjectItemSerializer::UNEXPECTED_REDACTION_METRIC
    end

    test "logs when no redactions were made from a paginated context" do
      MemexProjectItemPrefiller
        .new(
          [@issue_item],
          columns: @memex.default_view.visible_columns
        )
        .prefill

      serializer = MemexProjectItemSerializer.new(
        viewer: @user,
        memex: @memex,
        items: [@issue_item],
        from_paginated_context: true
      )

      refute_logged(Body: MemexProjectItemSerializer::UNEXPECTED_REDACTION_LOG_MESSAGE) do
        result = serializer.result
        refute result.items.any? { |i| i[:contentType] == MemexProjectItem::REDACTED_ITEM_TYPE }
      end

      assert_dogstats_increment 1, MemexProjectItemSerializer::ZERO_REDACTIONS_METRIC
    end
  end
end
