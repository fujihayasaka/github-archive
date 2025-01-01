# typed: true
# frozen_string_literal: true

module MemexProjectItem::ColumnDependency
  extend ActiveSupport::Concern
  extend T::Sig
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
  def set_column_value(column, new_value, actor, append_only = false, suppress_hydro_events: false)
    # For communicating with related event triggers down the stack
    GitHub.context.push(actor_id: actor.id)
    if content&.respond_to?(:modifying_user=)
      content.modifying_user = actor
    end

    case column&.data_type&.to_sym
    when :title
      set_title_column_value(column, new_value, actor)
    when :assignees
      set_assignees_column_value(new_value)
    when :labels
      set_labels_column_value(new_value)
    when :milestone
      set_milestone_column_value(column, new_value, actor)
    when :tracked_by
      set_tracked_by_column_value(new_value, actor, append_only)
    when :issue_type
      set_issue_type_column_value(new_value, actor)
    when :parent_issue
      set_parent_issue_column_value(new_value, actor)
    when :single_select, :text, :number, :date, :iteration
      set_generic_type_column_value(column, new_value, actor, suppress_hydro_events:)
    else
      false
    end
  end

  # Public: forces the column value for a specific column to be removed.
  #
  # column - MemexProjectColumn whose value we should set
  # actor - User who requested that we set the column value
  #
  # Returns Boolean for whether or not the update succeeded
  def clear_column_value(column, actor)
    set_column_value(column, nil, actor)
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

    success = self.set_column_value(column, new_value, actor)
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

  private

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

  # Private: Sets the value of a MemexProjectColumn whose data_type is :title.
  #
  # Any :title column is system-defined, so this will set the `title` field on
  # the underlying content object. It will also make a denormalized copy of the
  # value of that field in `memex_project_column_values`.
  #
  # title_column - The Title column for this item's memex.
  # new_value - Hash containing a :title key. The value of that key indicates
  #   the new title for this MemexProjectItem's content.
  # actor - User who will be set as the creator of the title value.
  #   This is required by MemexProjectColumnValue and so is included for
  #   backwards-compatibility, but it doesn't have meaning for non-generic
  #   columns like this one.
  #
  # Returns Boolean for whether or not the operation succeeded.
  def set_title_column_value(title_column, new_value, actor)
    return false if new_value&.try(:fetch, :title).blank?

    title_receiver = content.is_a?(PullRequest) ? content.issue : content
    if title_receiver&.respond_to?(:modifying_user=)
      title_receiver.modifying_user = actor
    end

    canonical_write_successful = title_receiver.update(title: new_value[:title])

    unless canonical_write_successful
      self.errors.add(:base, title_receiver.errors.full_messages.to_sentence)
      return false
    end

    denormalized_write_successful = cache_title_column_value(
      title_column,
      denormalized_title_value,
      actor
    )

    denormalized_write_successful
  end

  # Private: Sets the value of a column
  # Relies on validations on the `MemexProjectColumnValue` model, based on data type.
  #
  # column - MemexProjectColumn whose data_type is :text, :single_select or :number
  # new_value - String representing the value that this MemexProjectItem should
  #   have in the given column.
  # actor - User who will be set as the initial creator of the generic column value.
  #
  # Returns Boolean for whether or not the operation succeeded.
  sig do
    params(
      column: MemexProjectColumn,
      new_value: T.nilable(T.any(String, Float, Integer)),
      actor: User,
      suppress_hydro_events: T::Boolean
    ).returns(T::Boolean)
  end
  def set_generic_type_column_value(column, new_value, actor, suppress_hydro_events: false)
    retry_on_find_or_create_error do
      unless new_value.present?
        target_column_value = find_column_value(column.id)
        return true if target_column_value.nil?
        target_column_value.disable_hydro_event_instrumentation = suppress_hydro_events
        return !!target_column_value.destroy&.destroyed?
      end

      target_column_value = find_column_value(column.id) || build_column_value(column.id, actor)
      target_column_value.disable_hydro_event_instrumentation = suppress_hydro_events
      return true unless target_column_value.present?

      # Note that this prefill is here to prevent extraneous queries on column-based
      # validation in MemexProjectColumnValue when we already have the column.
      # See this post for details on implementation: https://github.com/orgs/github/teams/engineering/discussions/467
      GitHub::PrefillAssociations.prefill_associations(target_column_value, :memex_project_column,
        available_records: [column])

      return true if target_column_value.update(value: new_value)
      errors.add(:column_value, "must be a valid value for #{column.data_type} column")
      false
    end
  end

  # Private: Sets the value of a column whose data_type is :assignees
  #
  # assignee_ids - Array of user_ids to set as assignees
  #
  # Returns Boolean for whether or not the operation succeeded.
  def set_assignees_column_value(assignee_ids)
    target = draft_issue_type? ? content : issue_for_content
    return false unless target

    assignees = User.where(id: assignee_ids).to_a
    target.assignees = assignees

    if target.errors[:assignees].present?
      assignee_logins = assignees.map(&:display_login).to_sentence
      self.errors.add(:base, "Could not be assigned to #{assignee_logins}.")
      return false
    end

    target.save
  end

  # Private: Sets the value of a column whose data_type is :labels
  #
  # labels_ids - Array of Label IDs to replace labels on the underlying content
  #
  # Returns Boolean for whether or not the operation succeeded.
  def set_labels_column_value(label_ids)
    return false unless issue_for_content

    labels = if label_ids.present?
      Label.where(id: label_ids, repository_id: issue_for_content.repository_id).to_a
    else
      []
    end

    if issue_for_content.replace_labels(labels)
      total_label_ids = label_ids&.count || 0
      success = issue_for_content.label_ids.count == total_label_ids
      self.errors.add(:base, "Not all labels could be found") unless success
      success
    else
      self.errors.add(:base, issue_for_content.errors.full_messages.to_sentence)
      false
    end
  end

  def set_issue_type_column_value(issue_type_id, actor)
    return false unless content.is_a?(Issue)
    owner = content.repository.owner

    unless content.can_set_type?(actor: actor)
      self.errors.add(:base, "You do not have permission to set the issue type for this item")
      return false
    end

    unless content.update(issue_type_id: issue_type_id)
      self.errors.add(:base, content.errors.full_messages.to_sentence)
      return false
    end

    true
  end

  def set_parent_issue_column_value(parent_issue_id, actor)
    return false unless content.is_a?(Issue)

    canonical_write_successful = if parent_issue_id.present?
      parent_issue = Issue.find_by(id: parent_issue_id)

      unless parent_issue
        self.errors.add(:base, "Parent issue does not exist")
        return false
      end

      relationship = content.add_or_replace_parent!(parent_issue, actor)

      unless relationship&.persisted?
        self.errors.add(:base, relationship.errors.full_messages.to_sentence)
        return false
      end

      true
    else
      content.parent.remove_sub_issue!(content)
    end

    unless canonical_write_successful
      self.errors.add(:base, content.errors.full_messages.to_sentence)
      return false
    end

    true
  # Unlike most sub-issues validations, max-height errors are raised in the `after_create` callback.
  rescue SubIssue::MaximumHeightError => e
    self.errors.add(:base, e.message)
    false
  end

  def set_milestone_column_value(milestone_column, milestone_id, actor)
    return false unless issue_for_content

    canonical_write_successful = if milestone_id.present?
      milestone = issue_for_content.repository.milestones.find_by(id: milestone_id)
      unless milestone
        self.errors.add(:base, "Milestone does not exist")
        return false
      end
      issue_for_content.update(milestone_id: milestone_id)
    else
      issue_for_content.update(milestone_id: nil)
    end

    unless canonical_write_successful
      self.errors.add(:base, issue_for_content.errors.full_messages.to_sentence)
      return false
    end

    denormalized_write_successful = cache_milestone_column_value(
      milestone_column,
      denormalized_milestone_value,
      actor
    )

    denormalized_write_successful
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
