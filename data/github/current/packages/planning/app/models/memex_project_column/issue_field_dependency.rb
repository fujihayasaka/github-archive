# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::IssueFieldDependency
  extend ActiveSupport::Concern

  extend T::Helpers
  requires_ancestor { MemexProjectColumn }

  # List of supported issue field data types for projects.
  #
  # Issue fields have their own set of data types, but not all of them are supported yet in MemexProjectColumn.
  SUPPORTED_ISSUE_FIELD_DATA_TYPES = T.let(
    %w(
      text
      single_select
      number
      date
    ),
    T::Array[String]
  )

  # Returns the list of columns that should not be modified by the user when updating an issue field.
  # These columns are considered read-only and should not be changed.
  READ_ONLY_ISSUE_FIELD_COLUMNS = T.let(
    %w(
      name
      name_slug
      user_defined
      visible
      data_type
      settings
      creator_id
      issue_field_id
    ),
    T::Array[String]
  )

  # Returns the list of columns that may be updated when syncing updates from an issue field to a project column.
  ISSUE_FIELD_SYNC_COLUMNS = T.let(
    %w(
      name
      name_slug
    ),
    T::Array[String]
  )

  included do
    T.bind(self, T.class_of(MemexProjectColumn))

    validate :issue_field_read_only_properties_not_updated, on: :update
    validate :issue_field_belongs_to_project_owner
    validate :issue_field_data_type_supported
  end

  class_methods do
    sig do
      params(
        memex_project: MemexProject,
        issue_field: IssueField,
      ).returns(T.nilable(MemexProjectColumn))
    end
    def build_readonly_issue_field(memex_project:, issue_field:)
      T.bind(self, T.class_of(MemexProjectColumn))

      # While we have a validation for `data_type` to handle this for us in most cases, we'd like to avoid issuing any
      # MySQL queries to check the validity of the issue field.
      return unless supported_issue_field_type?(issue_field.data_type.to_s)
      return unless memex_project.owner_id == issue_field.owner_id

      column = new(memex_project:, issue_field:)
      column.readonly!
      column.denormalize_issue_field(calculate_position: false)
      column
    end

    # Enables issue field sync mode, allowing updates to specific read-only columns.
    sig { params(blk: T.proc.void).returns(T.untyped) }
    def with_issue_field_sync(&blk)
      begin
        Thread.current[:syncing_issue_field] = true
        yield
      ensure
        Thread.current[:syncing_issue_field] = false
      end
    end

    # Returns whether or not we are currently updating from an issue field
    sig { returns(T::Boolean) }
    def syncing_issue_field?
      Thread.current[:syncing_issue_field] || false
    end

    sig { params(data_type: String).returns(T::Boolean) }
    def supported_issue_field_type?(data_type)
      SUPPORTED_ISSUE_FIELD_DATA_TYPES.include?(data_type)
    end
  end

  sig { returns(T::Boolean) }
  def issue_field?
    issue_field_id? && issue_field_id > 0
  end

  sig { returns(T::Boolean) }
  def valid_issue_field_changes?
    invalid_issue_field_changes.blank?
  end

  sig { returns(T::Array[String]) }
  def invalid_issue_field_changes
    if MemexProjectColumn.syncing_issue_field?
      changed & READ_ONLY_ISSUE_FIELD_COLUMNS - ISSUE_FIELD_SYNC_COLUMNS
    else
      changed & READ_ONLY_ISSUE_FIELD_COLUMNS
    end
  end

  sig { void }
  private def issue_field_belongs_to_project_owner
    return unless issue_field?
    return if issue_field&.owner == memex_project&.owner

    errors.add(:issue_field, :not_belonging_to_project_owner)
  end

  sig { void }
  private def issue_field_data_type_supported
    return unless issue_field?
    return if SUPPORTED_ISSUE_FIELD_DATA_TYPES.include?(data_type)

    errors.add(:data_type, :unsupported_issue_field_data_type)
  end

  sig { void }
  private def issue_field_read_only_properties_not_updated
    return if !issue_field? || valid_issue_field_changes?

    invalid_issue_field_changes.each do |column|
      errors.add(column, :read_only)
    end
  end
end
