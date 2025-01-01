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
  # Returns Boolean for whether or not the update succeeded.
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
    # For communicating with related event triggers down the stack
    GitHub.context.push(actor_id: actor.id)
    if content&.respond_to?(:modifying_user=)
      content.modifying_user = actor
    end

    legacy_result = \
      case column&.data_type&.to_sym
      when :title,
        :assignees,
        :labels,
        :milestone,
        :issue_type,
        :parent_issue,
        :single_select,
        :text,
        :number,
        :date,
        :iteration

        T.must(column&.to_field).update_field_value(
          item: T.cast(self, MemexProjectItem),
          new_value:,
          actor:,
          suppress_hydro_events:,
          skip_elasticsearch_updates:
        )
      when :tracked_by
        set_tracked_by_column_value(new_value, actor, append_only)
      else
        false
      end

    if legacy_result.try(:mysql).try(:succeeded?)
      # We used the new `Writeable` interface and MySQL the write succeeded.
      #
      # In this case, we return the `Writeable::Result` object because it is both truthy for backwards compatibility
      # with callers that expect a boolean result, and contains additional information about the result of the write
      # to Elasticsearch for new callers that care about that.
      legacy_result
    elsif !legacy_result.try(:mysql) && legacy_result
      # We used the legacy interface and the MySQL write suceeded.
      #
      # Again return a `Writeable::Result` object because that is truthy for backwards compatibility with callers
      # that expect a boolean.
      MemexProjectColumn::Interface::Writeable::Result.new(
        mysql: MemexProjectColumn::Interface::Writeable::PartialResult.success
      )
    else
      # Regardless of the interface we used, the MySQL write failed so we must return a falsy object for backwards
      # compatibility.
      #
      # Once the transition to the `Writeable` interface is complete, this case (and this whole if/else block) should
      # be removed and we should always return the `Writeable::Result` object. That work is tracked in:
      # https://github.com/github/projects-platform/issues/2508
      nil
    end
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

  def cache_title_column_value(title_column, new_title_json, actor, disable_webhook_instrumentation: false)
    set_json_value(
      title_column,
      new_title_json,
      new_title_json[:title][:raw],
      actor,
      disable_webhook_instrumentation: disable_webhook_instrumentation
    )
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
        disable_webhook_instrumentation: disable_webhook_instrumentation
      )
    end
  end

  def build_denormalized_column_values(actor)
    success = cache_title_column_value(
      memex_project&.columns&.find(&:title?),
      denormalized_title_value,
      actor,
      disable_webhook_instrumentation: true,
    )

    if can_have_milestone?
      success &&= cache_milestone_column_value(
        memex_project&.columns&.find(&:milestone?),
        denormalized_milestone_value,
        actor,
        disable_webhook_instrumentation: true,
      )
    end

    success
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

  private

  sig { params(column_id: T.nilable(Integer), actor: User).returns(MemexProjectColumnValue) }
  def build_column_value(column_id, actor)
    memex_project_column_values.build(memex_project_column_id: column_id, creator: actor)
  end

  sig { params(column_id: T.nilable(Integer)).returns(T.nilable(MemexProjectColumnValue)) }
  def find_preloaded_column_value(column_id)
    memex_project_column_values.detect { |column_value| column_value.memex_project_column_id == column_id }
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

  # Private: Sets the value in issues-graph whose data_type is :tracked_by
  #
  # tracked_by_parents - Array of strings with tracked_by parent information to connect self to parent (string
  # expected: org/repo#number, user/repo#number)
  #
  # Returns Boolean for whether or not the operation succeeded.
  def set_tracked_by_column_value(parents_param, actor, append_only = false)
    return false unless (project = memex_project)
    return false unless GitHub.flipper[:tasklist_block].enabled?(project.owner)
    return false if draft_issue?
    return false if content_type == MemexProjectItem::PULL_REQUEST_TYPE

    child = content
    return false unless child

    tracked_by_parents_to_add, tracked_by_parents_to_remove = diff_tracked_by_values(child, parents_param, actor)

    tracked_by_parents_to_add.each do |parent|
      if memex_project&.owner&.feature_enabled?(:tasklist_block_markdown_at_rest)
        TasklistBlockCommands::AppendChildToParent.new(
          child: child,
          parent: parent,
          actor: actor,
        ).call
        next
      end

      return false unless parent_tracking_blocks = get_tracking_blocks_by_parent(project.owner_id, parent.id)
      case parent_tracking_blocks.length
      when 0
        # If no tasklist, create new tasklist
        child.create_tasklist_in_parent(parent: parent)
      else
        # If has a tasklist, add to last tasklist
        block_id = parent_tracking_blocks&.last&.dig(:key, :primaryKey, :uuid)
        child.add_to_tasklist_in_parent(owner_id: project.owner_id, parent: parent, block_id: block_id)
      end
    end

    # Skip removal logic if the client has requested an append only update
    return true if append_only

    tracked_by_parents_to_remove.each do |parent|
      if memex_project&.owner&.feature_enabled?(:tasklist_block_markdown_at_rest)
        TasklistBlockCommands::RemoveChildFromParent.new(
          child: child,
          parent: parent,
          actor: actor,
        ).call
        next
      end

      return false unless parent_tracking_blocks = get_tracking_blocks_by_parent(project.owner_id, parent.id)
      item_uuid = T.let(nil, T.nilable(String))
      matching_block = parent_tracking_blocks.find do |block|
        matching_issue = block[:issues].find { |issue| issue[:key][:itemId] == child.id }
        if matching_issue
          item_uuid = matching_issue[:key][:primaryKey][:uuid]
        end
      end
      block_id = matching_block&.dig(:key, :primaryKey, :uuid)
      return false unless block_id && item_uuid

      child.remove_from_tasklist_in_parent(owner_id: project.owner_id, parent: parent, block_id: block_id,
        item_uuid: item_uuid)
    end
  end

  # Private: Retrieves the value of the given MemexProjectColumn for this object.
  #
  # The receiver of this method should be a valid `content` association of a MemexProjectItem.
  #
  # column - MemexProjectColumn
  # require_prefilled_associations - Whether or not we should raise an exception if we're about to
  #   serialize an association that has not already been prefilled (meaning we're likely to generate
  #   an N+1).
  # prefilled_associations - MemexProjectItem::PrefilledAssociations object that, when provided,
  #   will be used to make this method more efficient by using the data contained in this object
  #   and other denormalized data wherever possible.
  #
  # Returns an object representing the value for the given column.
  def special_type_column_value(column, require_prefilled_associations: true, prefilled_associations: nil, redacted_issue_ids: [])
    unless prefilled_associations
      return completion if column.name == MemexProjectColumn::TRACKS_COLUMN_NAME

      begin
        # calling tracked_by_items directly (which will have been prefilled)
        if column.name == MemexProjectColumn::TRACKED_BY_COLUMN_NAME
          return tracked_by_items&.reject { |i| redacted_issue_ids.include?(i.issue_id) }&.map(&:to_tracked_by_item) || []
        end
      rescue MemexProjectItem::ItemPrefillError
        return []
      end

      return content.memex_special_type_column_value(
        column,
        require_prefilled_associations: require_prefilled_associations,
        redacted_issue_ids: redacted_issue_ids
      )
    end

    ensure_preloaded_column_values! if require_prefilled_associations
    default_has_many_value = draft_issue? ? nil : []

    case column.data_type.to_sym
    when :assignees
      prefilled_associations
        .assignees(self, default_value: [])
        &.map(&:memex_column_hash)
    when :reviewers
      prefilled_associations
        .reviewers(self, default_value: default_has_many_value)
    when :labels
      prefilled_associations
        .labels(self, default_value: default_has_many_value)
        &.map(&:memex_column_hash)
    when :linked_pull_requests
      prefilled_associations
        .linked_pull_requests(self, default_value: default_has_many_value)
        &.reject { |pull_request| redacted_issue_ids.include?(pull_request.issue.id) }
        &.map(&:memex_column_hash)
    when :tracks
      prefilled_associations.completion(self)
    when :tracked_by
      prefilled_associations.tracked_by_items(self)
        &.reject { |tracked_by_item| redacted_issue_ids.include?(tracked_by_item.issue_id) }
        &.map(&:to_tracked_by_item)
    when :repository
      prefilled_associations.repository(self)&.memex_column_hash
    when :milestone
      prefilled_associations.milestone(self)
    when :title
      column_value = find_preloaded_column_value(column.id)
      column_value&.json_value
    when :issue_type
      prefilled_associations.issue_type(self)&.memex_column_hash
    when :parent_issue
      parent = prefilled_associations.parent_issue(self)
      return if redacted_issue_ids.include?(parent&.id)
      parent&.memex_column_hash
    when :sub_issues_progress
      prefilled_associations.sub_issues_progress(self)&.memex_column_hash&.transform_keys { |key| key.to_s.camelize(:lower).to_sym }
    else
      raise ArgumentError.new("Support for '#{column.data_type}' column has not been implemented")
    end
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
