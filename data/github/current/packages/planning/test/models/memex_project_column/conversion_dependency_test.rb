# typed: true
# frozen_string_literal: true

require "test_helper"

module MemexColumnDataTypeConversionTestHelpers
  extend ActiveSupport::Concern

  class_methods do

    sig { returns(T::Array[String]) }
    def all_data_types
      MemexProjectColumn.data_types.keys.map(&:to_s)
    end

    sig { returns(T::Array[String]) }
    def unconvertable_data_types
      all_data_types - MemexProjectColumn::ConversionDependency::ALLOWED_DATA_TYPE_CONVERSIONS.keys.map(&:to_s)
    end

    sig { params(data_type: T.any(Symbol, String)).returns(T::Array[String]) }
    def disallowed_conversion_data_types_for(data_type)
      allowed_data_type_conversions =
        MemexProjectColumn::ConversionDependency::ALLOWED_DATA_TYPE_CONVERSIONS[data_type.to_sym]
      result = all_data_types - [data_type.to_s]
      result -= allowed_data_type_conversions.map(&:to_s) if allowed_data_type_conversions
      result
    end
  end
end

class MemexProjectColumn::ConversionDependencyTest < GitHub::TestCase
  include MemexColumnDataTypeConversionTestHelpers

  fixtures do
    @memex = create(:memex_project)
    @assignees_column = @memex.find_column_by_name_or_id(MemexProjectColumn::ASSIGNEES_COLUMN_NAME)
    @labels_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LABELS_COLUMN_NAME)
    @number_column = create(:number_memex_column, memex_project: @memex)
    @date_column = create(:date_memex_column, memex_project: @memex)
    @single_select_column = create(:single_select_memex_column, memex_project: @memex)
    @iteration_column = create(:iteration_memex_column, memex_project: @memex)
    @milestone_column = @memex.find_column_by_name_or_id(MemexProjectColumn::MILESTONE_COLUMN_NAME)
    @repository_column = @memex.find_column_by_name_or_id(MemexProjectColumn::REPOSITORY_COLUMN_NAME)
    @title_column = @memex.find_column_by_name_or_id(MemexProjectColumn::TITLE_COLUMN_NAME)
    @text_column = create(:memex_project_column, memex_project: @memex, user_defined: true, data_type: :text)
    @tracked_by_column = @memex.find_column_by_name_or_id(MemexProjectColumn::TRACKED_BY_COLUMN_NAME)
    @linked_prs_column = @memex.find_column_by_name_or_id(MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME)
    @reviewers_column = @memex.find_column_by_name_or_id(MemexProjectColumn::REVIEWERS_COLUMN_NAME)
    @tracks_column = @memex.find_column_by_name_or_id(MemexProjectColumn::TRACKS_COLUMN_NAME)
    @issue_type_column = create(:issue_type_memex_project_column, memex_project: @memex)
    @parent_issue_column = @memex.find_column_by_name_or_id(MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME)
    @sub_issues_progress_column = @memex.find_column_by_name_or_id(MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME)
  end

  setup do
    @columns_by_data_type = HashWithIndifferentAccess.new(
      assignees: @assignees_column,
      labels: @labels_column,
      milestone: @milestone_column,
      repository: @repository_column,
      title: @title_column,
      linked_pull_requests: @linked_prs_column,
      reviewers: @reviewers_column,
      tracks: @tracks_column,
      tracked_by: @tracked_by_column,
      text: @text_column,
      single_select: @single_select_column,
      number: @number_column,
      date: @date_column,
      iteration: @iteration_column,
      issue_type: @issue_type_column,
      parent_issue: @parent_issue_column,
      sub_issues_progress: @sub_issues_progress_column,
    )
  end

  context "#data_type_conversion_key" do
    test "returns a string unique to each column" do
      conversion_key1 = @number_column.data_type_conversion_key
      assert_predicate conversion_key1, :present?

      conversion_key2 = @date_column.data_type_conversion_key
      assert_predicate conversion_key2, :present?

      refute_equal conversion_key1, conversion_key2
    end

    test "returns nil for a new column" do
      column = build(:number_memex_column, memex_project: @memex)
      assert_nil column.data_type_conversion_key
    end
  end

  context "#changing_data_type?" do
    test "returns false for a new column" do
      column = build(:number_memex_column, memex_project: @memex)
      refute_predicate column, :changing_data_type?
    end

    test "returns false when no data conversion key-value record exists for the column" do
      Memex::KV.store.del(@number_column.data_type_conversion_key)
      refute_predicate @number_column, :changing_data_type?
    end

    test "returns true when a data conversion key-value record exists for the column" do
      Memex::KV.store.set(@number_column.data_type_conversion_key, "yep")
      assert_predicate @number_column, :changing_data_type?
    end
  end

  context "#mark_as_changing_data_type" do
    test "returns false and sets no key-value record for a new column" do
      Memex::KV.store.expects(:set).never
      column = build(:number_memex_column, memex_project: @memex)
      refute column.mark_as_changing_data_type(:text)
    end

    test "returns true and sets a key-value record for an existing column" do
      assert_nil Memex::KV.store.get(@number_column.data_type_conversion_key).value!

      assert @number_column.mark_as_changing_data_type(:text)

      assert_equal "text", Memex::KV.store.get(@number_column.data_type_conversion_key).value!
      assert_predicate @number_column, :skip_data_type_converting_check
    end
  end

  context "#mark_as_data_type_change_finished" do
    test "no-op for new column" do
      column = build(:number_memex_column, memex_project: @memex)
      Memex::KV.store.expects(:del).never
      column.mark_as_data_type_change_finished
    end

    test "deletes the key-value record for an existing column" do
      Memex::KV.store.set(@number_column.data_type_conversion_key, "yep")

      @number_column.mark_as_data_type_change_finished

      assert_nil Memex::KV.store.get(@number_column.data_type_conversion_key).value!
      refute_predicate @number_column, :skip_data_type_converting_check
    end
  end

  context "validations" do
    MemexProjectColumn::ConversionDependency::ALLOWED_DATA_TYPE_CONVERSIONS.each do |old_data_type, new_data_types|
      context "converting data_type=#{old_data_type} column" do
        new_data_types.each do |new_data_type|
          test "allows changing to #{new_data_type} data_type" do
            column = @columns_by_data_type[old_data_type]
            refute_nil column, "expected to have a data_type=#{old_data_type} column"

            column.data_type = new_data_type

            column.valid? # run validations
            assert_empty column.errors[:data_type]
          end

          test "disallows changing to #{new_data_type} when conversion is already in progress" do
            column = @columns_by_data_type[old_data_type]
            refute_nil column, "expected to have a data_type=#{old_data_type} column"
            Memex::KV.store.set(column.data_type_conversion_key, "foo")

            column.data_type = new_data_type

            refute_predicate column, :valid?
            assert_includes column.errors[:data_type], "is already being changed"

            column.skip_data_type_converting_check = true
            column.valid? # run validations
            assert_empty column.errors[:data_type], "should allow changing data_type when skipping converting check"
          end
        end

        disallowed_conversion_data_types_for(old_data_type).each do |new_data_type|
          test "disallows changing to #{new_data_type} data_type" do
            column = @columns_by_data_type[old_data_type]
            refute_nil column, "expected to have a data_type=#{old_data_type} column"

            column.data_type = new_data_type

            refute_predicate column, :valid?
            assert_includes column.errors[:data_type], "cannot be changed to #{new_data_type.to_s.humanize.downcase}"
          end
        end
      end
    end

    unconvertable_data_types.each do |old_data_type|
      context "converting data_type=#{old_data_type} column" do
        disallowed_conversion_data_types_for(old_data_type).each do |new_data_type|
          test "disallows changing to #{new_data_type} data_type" do
            column = @columns_by_data_type[old_data_type]
            refute_nil column, "expected to have a data_type=#{old_data_type} column"

            column.data_type = new_data_type

            refute_predicate column, :valid?
            assert_includes column.errors[:data_type], "cannot be changed"
          end
        end
      end
    end
  end
end
