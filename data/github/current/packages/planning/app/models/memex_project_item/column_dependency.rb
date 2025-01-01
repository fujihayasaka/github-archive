# typed: true
# frozen_string_literal: true

module MemexProjectItem::ColumnDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { MemexProjectItem }

  REDACTED_ITEM_TITLE = "You can't see this item"

  # Maps a column's data type to the corresponding hash key path. This is used to extract
  # the string representation of an item's column value obtained from MemexProjectItem#column_values.value.
  COLUMN_VALUE_KEYS = {
    assignees: :value,
    single_select: [:value, "id"],
    iteration: [:value, "id"],
    date: [:value, "value"],
    repository: [:value, :nameWithOwner],
    text: [:value, "raw"],
    number: [:value, "value"],
    milestone: [:value, :title],
    labels: :value,
    title: [:value, "title", "html"],
    issue_type: [:value, :name],
    parent_issue: [:value, :title],
    sub_issues_progress: :value,
  }.freeze

  included do
    T.bind(self, T.class_of(MemexProjectItem))

    has_many :memex_project_column_values, inverse_of: :memex_project_item
  end

  def column_values(columns:, require_prefilled_associations:, prefilled_associations: nil, redacted_issue_ids: [])
    columns.map do |column|
      value = if redacted_item_type? && column.name == MemexProjectColumn::TITLE_COLUMN_NAME
        { title: REDACTED_ITEM_TITLE }
      elsif redacted_item_type?
        nil
      elsif column.special_type?
        special_type_column_value(
          column,
          require_prefilled_associations: require_prefilled_associations,
          prefilled_associations: prefilled_associations,
          redacted_issue_ids: redacted_issue_ids
        )
      elsif column.generic_type?
        generic_type_column_value(
          column,
          require_prefilled_associations: require_prefilled_associations,
        )
      end

      {
        memexProjectColumnId: column.synthetic_id,
        value: value
      }
    end
  end

  # Public: Returns a text representation of the item's value for the given column.
  # NOTE: This method only supports groupable column types. Non-groupable types will return nil.
  #
  # column - MemexProjectColumn for the column we're trying to get the value for
  # require_prefilled_associations - Boolean indicating whether or not prefilled associations should be enforced.
  # prefilled_associations - MemexProjectItem::PrefilledAssociation
  # redacted_issue_ids - Array of issue ids that are currently redacted.
  #
  # This will be getting refactored to replace the switch with calls to the column class to allow it to fetch
  # the value and format it correctly.
  #
  # Returns a String, or nil if the item has no value for the given column/is non-groupable.
  def column_value(column, require_prefilled_associations: true, prefilled_associations: nil, redacted_issue_ids: [])
    data = column_values(
      columns: [column],
      require_prefilled_associations: require_prefilled_associations,
      prefilled_associations: prefilled_associations,
      redacted_issue_ids: redacted_issue_ids
    )&.first

    dig_by = COLUMN_VALUE_KEYS[column.data_type.to_sym]
    return unless data && dig_by

    value = data.dig(*dig_by)
    return unless value

    case column.data_type
    when "assignees"
      logins = value.map { |assignee| assignee[:login] }.uniq.sort
      logins.blank? ? nil : logins.join(", ")
    when "single_select"
      column.settings.dig("options").find { |o| o["id"] == value }&.dig("name")
    when "iteration"
      iterations = column.settings_all_iterations
      iterations.find { |i| i["id"] == value }&.dig("title")
    when "date"
      value&.to_date&.strftime("%b %-d, %Y")
    when "repository", "text", "milestone", "issue_type", "parent_issue"
      value
    when "number"
      # This method is deriving a string representation of the number, so we need to round it to the precision
      # and ensure it doesn't have trailing zeros or un-necessary decimal points.  This method should be considered
      # presentation-level and should most likely be moved somewhere outside of the model during a refactor.
      number_to_rounded(
        value,
        precision: MemexProjectColumnValue::NUMBER_VALUE_PRECISION,
        strip_insignificant_zeros: true
      )
    when "labels"
      value.map { |label| label[:nameHtml] }.join(", ")
    when "title"
      value
    when "sub_issues_progress"
      value&.dig(:percentCompleted)&.to_s
    end
  end

  # Public: Sets the value of a column.
  #
  # column - MemexProjectColumn whose value we should set
  # new_value - Object representing the updated value. The specific type of this object depends on
  #   the column. For some columns, passing a blank value here will delete the column value if
  #   it exists.
  # actor - User who requested that we set the column value.
  # append_only - For a column value which is an array, determines if the update should 1. Append the provided values
  # to the existing value or 2. overwrite the existing value
  #
  # Returns a MemexProjectColumn::Interface::Writeable::Result instance when the MySQL write succeeds (regardless of
  # the result of the ES write), nil is returned when the MySQL result fails.
  sig do
    params(
      column: T.nilable(MemexProjectColumn),
      new_value: T.untyped,
      actor: User,
      append_only: T.nilable(T::Boolean),
      suppress_hydro_events: T::Boolean,
      skip_elasticsearch_updates: T::Boolean
    )
    .returns(T.nilable(MemexProjectColumn::Interface::Writeable::Result))
  end
  def set_column_value(column, new_value, actor, append_only = false, suppress_hydro_events: false, skip_elasticsearch_updates: true)
    return unless (field = column&.to_field)
    return unless field.class.writeable?

    # For communicating with related event triggers down the stack
    GitHub.context.push(actor_id: actor.id)
    if (issue = issue_for_content)
      issue.modifying_user = actor
    end

    result = field.update_field_value(
      item: T.cast(self, MemexProjectItem),
      new_value:,
      actor:,
      suppress_hydro_events:,
      skip_elasticsearch_updates:
    )
    return unless result.mysql.succeeded?

    result
  end

  # Public: forces the column value for a specific column to be removed.
  #
  # column - MemexProjectColumn whose value we should set
  # actor - User who requested that we set the column value
  #
  # Returns Boolean for whether or not the update succeeded
  def clear_column_value(column, actor)
    set_column_value(column, nil, actor, skip_elasticsearch_updates: false)
  end

  # Finds a column by ID and sets the value if it exists
  #
  # column_id - MemexProjectColumnId to look up
  # new_value - Object representing the updated value
  #
  # Returns http status code and error messages
  def set_column_value_if_found(column_id, new_value, actor)
    column = memex_project&.find_column_by_name_or_id(column_id)
    [:not_found, "Column not found"] unless column

    success = self.set_column_value(column, new_value, actor, skip_elasticsearch_updates: false)
    [success ? :ok : :unprocessable_entity, self.errors.full_messages]
  end

  # queues a job to set the value for each column
  # in the columns collection for a persisted memex_project_item
  def queue_set_column_values(columns, creator, &is_flagged_in)
    return unless id && columns&.any?
    MemexProjectItemSetColumnsJob.perform_later(id, columns, creator.id)
  end

  sig do
    params(
      title_column: MemexProjectColumn,
      new_title_json: T::Hash[Symbol, T.untyped],
      actor: User,
      disable_webhook_instrumentation: T::Boolean
    ).returns(T::Boolean)
  end
  def cache_title_column_value(title_column, new_title_json, actor, disable_webhook_instrumentation: false)
    set_json_value(
      title_column,
      new_title_json,
      new_title_json[:title][:raw],
      actor,
      disable_webhook_instrumentation:,
    )
  end

  sig do
    params(
      milestone_column: MemexProjectColumn,
      new_milestone_json: T.nilable(T::Hash[Symbol, T.untyped]),
      actor: User,
      disable_webhook_instrumentation: T::Boolean
    ).returns(T::Boolean)
  end
  def cache_milestone_column_value(milestone_column, new_milestone_json, actor, disable_webhook_instrumentation: false)
    if new_milestone_json.nil?
      memex_project_column_values
        .destroy_by(memex_project_column_id: milestone_column.id)
        .all?(&:destroyed?)
    else
      set_json_value(
        milestone_column,
        new_milestone_json,
        new_milestone_json[:value][:id],
        actor,
        disable_webhook_instrumentation:,
      )
    end
  end

  sig { params(column_id: T.nilable(Integer), actor: User).returns(MemexProjectColumnValue) }
  def find_or_build_column_value(column_id, actor)
    find_column_value(column_id) || build_column_value(column_id, actor)
  end

  sig { params(column_id: T.nilable(Integer)).returns(T.nilable(MemexProjectColumnValue)) }
  def find_column_value(column_id)
    if association(:memex_project_column_values).loaded?
      find_preloaded_column_value(column_id)
    else
      memex_project_column_values.find_by(memex_project_column_id: column_id)
    end
  end

  sig { params(column_id: T.nilable(Integer)).returns(T.nilable(MemexProjectColumnValue)) }
  def find_preloaded_column_value(column_id)
    memex_project_column_values.detect { |column_value| column_value.memex_project_column_id == column_id }
  end

  # Indicates whether to bypass milestone denormalization for this item.
  #
  # When true:
  # - Assumes a pre-populated `MemexProjectColumnValue` exists for the milestone.
  # - Prevents `build_denormalized_column_values` from inserting a duplicate milestone entry.
  #
  # Use case:
  # - You’re creating a new item with a user-supplied milestone value that differs from the content’s
  #   current milestone.
  # - Iterating `memex_project_column_values` will mark the association as loaded, which can block
  #   the denormalization pipeline from updating the milestone reference before persistence.
  sig { returns(T::Boolean) }
  attr_accessor :skip_milestone_denormalization

  sig { returns(T::Boolean) }
  def skip_milestone_denormalization?
    !!@skip_milestone_denormalization
  end

  private

  # Determines if the item's `content` association has changed in a way that requires us to rebuild the denormalized
  # column values (e.g. Title and Milestone).
  #
  # Returns true if the `content_type` or `content_id` has changed. Even if `content_id` stays the same
  # (because the new `content_type` happens to have a record with that same ID), a change in `content_type`
  # will still return true.
  sig { returns(T::Boolean) }
  def build_denormalized_column_values?
    content_type_changed? || content_id_changed?
  end

  sig { returns(T::Boolean) }
  def build_denormalized_column_values
    columns = T.must(memex_project).columns
    title_column = T.must(columns.find(&:title?))

    success = cache_title_column_value(
      title_column,
      denormalized_title_value,
      T.must(creator),
      disable_webhook_instrumentation: true,
    )

    if !skip_milestone_denormalization? && can_have_milestone?
      milestone_column = T.must(columns.find(&:milestone?))
      success &&= cache_milestone_column_value(
        milestone_column,
        denormalized_milestone_value,
        T.must(creator),
        disable_webhook_instrumentation: true,
      )
    end

    unless success
      errors.add(:base, :build_denormalized_column_values_failed)
      throw(:abort)
    end

    success
  end

  sig { params(column_id: T.nilable(Integer), actor: User).returns(MemexProjectColumnValue) }
  def build_column_value(column_id, actor)
    memex_project_column_values.build(memex_project_column_id: column_id, creator: actor)
  end

  sig do
    params(
      column: MemexProjectColumn,
      json_value: T.untyped,
      legacy_value: T.untyped,
      actor: User,
      disable_webhook_instrumentation: T::Boolean
    ).returns(T::Boolean)
  end
  def set_json_value(column, json_value, legacy_value, actor, disable_webhook_instrumentation: false)
    column_value = find_or_build_column_value(column.id, actor)
    column_value.disable_webhook_event_instrumentation = disable_webhook_instrumentation
    GitHub::PrefillAssociations.prefill_associations([column_value], :memex_project_column,
      available_records: [column])

    if self.persisted?
      success = column_value.update(json_value: json_value, value: legacy_value)

      unless success
        self.errors.add(:base, column_value.errors.full_messages.to_sentence)
      end

      success
    else
      column_value.json_value = json_value
      column_value.value = legacy_value
      true
    end
  end

  sig do
    params(
      column: MemexProjectColumn,
      require_prefilled_associations: T::Boolean,
      prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
      redacted_issue_ids: T::Array[Integer]
    ).returns(T.nilable(T.any(MemexProjectColumn::Interface::Serializable::JSONValue, T::Array[MemexProjectColumn::Interface::Serializable::JSONValue])))
  end
  def special_type_column_value(column, require_prefilled_associations: true, prefilled_associations: nil, redacted_issue_ids: [])
    T.bind(self, MemexProjectItem)

    if require_prefilled_associations
      # We will be moving to ActiveRecord::Core#strict_loading! once https://github.com/rails/rails/pull/55002 is merged.
      #
      # As a result, the following implementation of prefilled association enforcement is for backwards compatibility
      # purposes and was previously delegated to the underlying content model.
      if prefilled_associations
        ensure_preloaded_column_values!
      else
        skip_preloaded_association_requirement = if pull_request?
          # PullRequest items do not support the following columns and their referenced special types.
          column.linked_pull_requests? || column.parent_issue? || column.sub_issues_progress? || column.reviewers?
        elsif issue?
          # Issue items do not support the following columns and their referenced special types.
          column.reviewers?
        else
          false
        end

        issue_for_content&.ensure_preloaded_association!(column) unless skip_preloaded_association_requirement
      end
    end

    field = T.cast(column.to_field, MemexProjectColumn::Interface::SpecialTypeSerializable)
    field.json_value(self, prefilled_associations:, redacted_issue_ids:)
  end

  # Private: Retrieves the value of a user-defined column.
  #
  # column - MemexProjectColumn whose value we should retrieve.
  # require_prefilled_associations - Whether or not we should raise an exception if we're about to
  #   retrieve a value before loading the `memex_project_column_values` association (meaning we're
  #   likely to generate an N+1).
  #
  # Returns String representing the value of a user-defined column, or nil if no value exists for
  # that column.
  def generic_type_column_value(column, require_prefilled_associations: true)
    ensure_preloaded_column_values! if require_prefilled_associations
    column_value = find_preloaded_column_value(column.id)
    column_value&.json_value
  end

  # Used only in tests to report that a proposed operation is not efficient.
  class AssociationRefused < StandardError
    def initialize
      super(
        "Refusing to map over unloaded :memex_project_column_values association: " +
        "please prefill this association efficiently before calling this method."
      )
    end
  end

  def ensure_preloaded_column_values!
    if Rails.env.test? && !self.association(:memex_project_column_values).loaded? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      raise AssociationRefused
    end
  end
end
