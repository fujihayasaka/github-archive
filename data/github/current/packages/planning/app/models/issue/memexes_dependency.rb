# typed: true
# frozen_string_literal: true

module Issue::MemexesDependency
  extend T::Helpers
  extend ActiveSupport::Concern
  include MemexProjectItem::Content
  include MemexProjectColumn::Interface::Groupable::Metadata
  include MemexProjectColumn::Interface::Sliceable::Metadata
  include MemexProjectColumn::Interface::Serializable
  include GitHub::Tracing

  requires_ancestor { Issue }

  trace_method :memex_content_hash

  # Arbitrary maximum number of projects for which we should use :batching authorisation method.
  # It was decided by comparing the performance of the two methods (More: https://github.com/github/github/pull/197430)
  AUTH_METHOD_TOGGLE_THRESHOLD = 30

  MEMEX_CONTENT_HASH_FIELD_MAP = {
    body: :body,
    body_html: :body_html,
    created_at: :created_at,
    updated_at: :updated_at,
    user: :user_memex_content_hash,
  }.freeze

  # Public: does the given user have access to the memex beta
  #
  # Returns a boolean
  def memex_projects_enabled?
    GitHub.projects_new_enabled?
  end

  # Public: Returns memex_project_items for the issue that the viewer has access to see.
  # See async_visible_memex_items_for for full implementation.
  #
  # viewer - The viewer to check access for.
  # include_archived - Whether to include archived items. Defaults to true.
  # allowed_owner - Optional - Name of the owner of the memexes to include when the memex owner does not match the owner of the issue. Default to nil.
  # prefill_template_predicate - Optional - Prefill the `is_template?` batch method on MemexProject
  #
  # Returns an Array of MemexProjectItem records.
  def visible_memex_items_for(viewer, include_archived: true, allowed_owner: nil, prefill_template_predicate: false)
    async_visible_memex_items_for(viewer, include_archived:, allowed_owner:, prefill_template_predicate:).sync
  end

  # Public: Returns a Promise resolving to an Array of MemexProjectItem records for
  # the issue that the viewer has access to see.
  #
  # Note: Currently returns all memex_project_items if the viewer has access to
  # memex items, but this logic may expand to cover additional permissions / gating.
  #
  # viewer - The viewer to check access for.
  # include_archived - Optional - Whether to include archived items. Defaults to true.
  # allowed_owner - Optional - Name of the owner of the memexes to include when the memex owner does not match the owner of the issue. Default to nil.
  # prefill_template_predicate - Optional - Prefill the `is_template?` batch method on MemexProject
  #
  # Returns a Promise.
  def async_visible_memex_items_for(viewer, include_archived: true, allowed_owner: nil, prefill_template_predicate: false)
    return Promise.resolve([]) unless GitHub.projects_new_enabled?

    async_repository.then do |repository|
      async_pull_request.then do |maybe_pull_request|
        content = maybe_pull_request || self

        ::Platform::Loaders::ProjectItemsForContent.load(
          repository: repository,
          content_type: content.class.name,
          content_id: content.id,
          include_archived: include_archived
        ).then do |items|
          next [] if items.blank?

          memex_projects = items.collect(&:memex_project).uniq

          async_accessible_projects = memex_projects.map do |memex_project|
            # As per https://github.com/github/memex/issues/5175, these are memexes owned by the same owner as the viewed issue if we don't have an allowed_owner
            # If allowed_owner is used, issue can also be owned by the optional owner given as parameter (see https://github.com/github/issues/issues/7473)
            next unless memex_project.owner_id == T.must(repository).owner_id || (allowed_owner && memex_project.owner.display_login == allowed_owner)
            next unless memex_project.deleted_at.nil?

            memex_project.async_readable_by?(viewer).then do |accessible|
              memex_project if accessible
            end
          end

          Promise.all(async_accessible_projects).then do |accessible_projects|
            next [] if accessible_projects.blank?

            accessible_projects_ids = accessible_projects.compact.index_by(&:id)
            filtered_items = items.filter_map do |item|
              item if accessible_projects_ids.key?(item.memex_project_id)
            end

            if prefill_template_predicate
              GitHub::PrefillAssociations.prefill_batch_method(filtered_items.collect(&:memex_project), :is_template?)
            end

            filtered_items
          end
        end
      end
    end
  end

  # Take Memex Project items and a viewer
  # returns a set of Memex Project ids that viewer has write access to
  def filter_writable_items(viewer, memex_project_items)
    return Set.new unless repository&.owner
    owner = T.must(repository&.owner)

    memex_project_ids = memex_project_items.pluck(:memex_project_id).uniq
    memex_projects = MemexProject.where(id: [memex_project_ids])

    writable_memex_projects =
      track_execution_time(["method:filter_writable_items", "size:#{memex_project_ids.size}"]) do
        owner.accessible_memexes_scope(
          memex_projects,
          viewer,
          "write",
          authorization_method_for(memex_project_ids)).to_a
      end

    Set.new(writable_memex_projects.map { |project| project.id })
  end

  # Returns the number of custom fields for a memex
  def count_user_defined_fields(memex_project_items)
    MemexProjectColumn
      .group(:memex_project_id)
      .where(memex_project_id: memex_project_items.map(&:memex_project_id))
      .where(user_defined: true)
      .count(:memex_project_id)
  end

  # Returns memex project that this user could add this issue to. Includes memex
  # projects that this issue is already in.
  #
  # ids: an array of memex project ids to check
  #
  # Returns an array of memex projects
  def potential_memex_projects_for(viewer, ids:)
    return [] unless viewer
    return [] unless repository&.owner

    owner = T.must(repository&.owner)

    scope = owner.memex_projects.open_projects.
      where(id: ids)

    accessible_memex_projects =
      track_execution_time(["method:potential_memex_projects_for", "size:#{ids.size}"]) do
        owner.accessible_memexes_scope(
          scope,
          viewer,
          "write",
          authorization_method_for(ids))
      end

    accessible_memex_projects.order(number: :desc)
  end

  def authorization_method_for(items = nil)
    return :enumeration if items.nil? || items.size > AUTH_METHOD_TOGGLE_THRESHOLD

    :batching
  end

  # Create memex project items for an issue or pull request
  #
  # issue_memex_project_ids: a hash of memex project ids associated with "on" in case the issue or PR must be linked to this project
  # issue_or_pr: an Issue or PullRequest object
  # viewer: user performing the action
  #
  # Could raise GitHub::Prioritizable::Context::LockedForRebalance
  def add_to_memex_projects!(issue_memex_project_ids, issue_or_pr, viewer)
    issue_memex_project_ids = (issue_memex_project_ids || {})
    return unless viewer
    return if issue_memex_project_ids.empty?
    return unless GitHub.projects_new_enabled?

    should_add_to_memex_projects = (issue_memex_project_ids)
        .values
        .any? { |v| v == "on" }

    return unless should_add_to_memex_projects


    memex_projects = self.potential_memex_projects_for(viewer, ids: issue_memex_project_ids.keys)
    memex_projects_over_limit = []
    memex_projects.each do |memex_project|
      if issue_memex_project_ids[memex_project.id.to_s] == "on"
        item = memex_project.build_item(issue_or_pull: issue_or_pr, creator: viewer)

        # This method will raise if the item is invalid. That is intended: the exception will
        # be handled by the issue and pull request controllers
        memex_project.save_with_priority!(item)
      end
    rescue ActiveRecord::RecordInvalid => error
      # If the target issue or pull request already exists in the MemexProject, we either want it to re-appear by
      # unarchiving it, or do nothing as it is not archived and visible in the MemexProject.
      if error.record&.errors&.of_kind?(:content_id, :taken)
        # Order of columns in find_by! is important for query to use correct index.
        memex_project_item = MemexProjectItem.find_by!(
          repository_id: issue_or_pr.repository_id,
          content: issue_or_pr,
          memex_project: memex_project,
        )

        memex_project_item.unarchive! if memex_project_item.archived?
      elsif error.record&.errors&.of_kind?(:base, :project_limit_reached)
        # Handle project limit reached error
        memex_projects_over_limit << memex_project
      else
        raise
      end
    end
    if memex_projects_over_limit.any?
      raise MemexProjectItem::ProjectLimitReachedError.new("#{memex_projects_over_limit.count} #{"projects".pluralize(memex_projects_over_limit.count)} exceeded its limit when trying to add new items", memex_projects_over_limit)
    end
    nil
  end

  # Remove issue or pull request from memex projects
  #
  # issue_memex_project_ids: a hash of memex project ids associated with "off"
  # issue_or_pr: an Issue or PullRequest object
  # viewer: user performing the action
  sig { params(issue_memex_project_ids: T.nilable(T::Hash[String, String]), issue_or_pr: T.any(Issue, PullRequest), viewer: T.nilable(User)).void }
  def remove_from_memex_projects!(issue_memex_project_ids, issue_or_pr, viewer)
    issue_memex_project_ids = (issue_memex_project_ids || {})
    return unless viewer
    return if issue_memex_project_ids.empty?
    return unless GitHub.projects_new_enabled?

    should_remove_from_memex_projects = (issue_memex_project_ids)
        .values
        .any? { |v| v == "off" }

    return unless should_remove_from_memex_projects

    memex_projects = self.potential_memex_projects_for(viewer, ids: issue_memex_project_ids.keys)
    memex_projects.each do |memex_project|
      if issue_memex_project_ids[memex_project.id.to_s] == "off"
        memex_project_item = MemexProjectItem.find_by(
          repository_id: issue_or_pr.repository_id,
          content: issue_or_pr,
          memex_project: memex_project,
        )
        next unless memex_project_item
        memex_project.destroy_project_items_later(viewer: viewer, item_ids: [memex_project_item.id])
      end
    end
    nil
  end

  # Returns the value of the status column for the given set of memex project items
  def status_column_values_by_memex_item_id(memex_project_items)
    project_columns_by_project_id = MemexProjectColumn
      .where(memex_project_id: memex_project_items.map(&:memex_project_id))
      .named(MemexProjectColumn::STATUS_COLUMN_NAME)
      .single_select
      .index_by(&:memex_project_id)

    project_column_values_by_project_item_id = MemexProjectColumnValue
      .where(memex_project_column_id: project_columns_by_project_id.values.map(&:id))
      .where(memex_project_item_id: memex_project_items.map(&:id))
      .index_by(&:memex_project_item_id)

    memex_project_items.reduce({}) do |result, item|
      project_column = project_columns_by_project_id[item.memex_project_id]
      project_column_value = project_column_values_by_project_item_id[item.id]
      options = project_column.settings_options_names_html
      option = project_column_value && options.find { |o| o["id"] == project_column_value.value }

      result[item.id] = {
        column_id: project_column.id,
        options: options,
        option: option
      }

      result
    end
  end

  def memex_suggestion_hash(last_interaction_at: nil, as_pull: false)
    result = {
      id: id,
      lastInteractionAt: last_interaction_at&.utc&.iso8601,
      number: number,
      state: state.to_s,
      title: title,
      type: "Issue",
      updatedAt: updated_at&.utc&.iso8601,
    }

    # Include `hasSubIssues` for issues only
    if !pull_request?
      total = sub_issue_list&.total
      result[:hasSubIssues] = total && total > 0
    end

    if as_pull && pull_request_id
      # Here we try to produce PullRequest#memex_suggestion_hash without actually loading a
      # PullRequest object. Tradeoff is that we can't tell draft status, and the updated at
      # timestamp in the result might be off, because it is actually the updated at timestamp
      # of this, the underlying issue, rather than the pull request object.
      result = result.merge({
        id: pull_request_id,
        isDraft: false,
        type: "PullRequest",
      })
    end

    unless pull_request_id
      # If the suggestion isn't a PR, include the issue state_reason
      result = result.merge({ stateReason: state_reason&.to_s })
    end

    result
  end

  # Implements MemexProjectItem::Content#memex_content_hash.
  # Fields are not yet supported
  def memex_content_hash(fields: [])
    content = {
        id: id,
        url: permalink,
      }.compact

    # To avoid additional queries that aren't needed, we don't include the global relay id for pull requests
    if !pull_request?
      content[:globalRelayId] = global_relay_id
    end

    fields.each_with_object(content) do |field, result|
      method = MEMEX_CONTENT_HASH_FIELD_MAP[field]
      next unless method.present? && respond_to?(method)
      result[field] = public_send(method)
    end
  end

  def csv_column_value
    permalink
  end

  def user_memex_content_hash
    user_or_ghost = user || User.ghost
    user_or_ghost.memex_column_hash
  end

  # DEPRECATED.
  #
  # This method will be removed over the course of https://github.com/github/i2c-backlog/issues/687.
  # Prefer using `MemexProjectItem#special_type_column_value` directly with the
  # `prefilled_associations` option.
  #
  # Implements MemexProjectItem::Content#memex_special_type_column_value.
  def memex_special_type_column_value(column, require_prefilled_associations: true, redacted_issue_ids: [])
    return [] if column.reviewers? # issues by definition do not have reviewers
    ensure_preloaded_association!(column) if require_prefilled_associations

    case column.name
    when MemexProjectColumn::ASSIGNEES_COLUMN_NAME, MemexProjectColumn::LABELS_COLUMN_NAME
      public_send(column.special_type_association)
        .sort_by { |i| i[column.content_sort_key]&.downcase }
        .map(&:memex_column_hash)
    when MemexProjectColumn::MILESTONE_COLUMN_NAME,
        MemexProjectColumn::REPOSITORY_COLUMN_NAME,
        MemexProjectColumn::TYPE_COLUMN_NAME
      public_send(column.special_type_association)&.memex_column_hash
    when MemexProjectColumn::LINKED_PULL_REQUESTS_COLUMN_NAME
      public_send(column.special_type_association)
        .map(&:pull_request)
        .reject { |pull_request| redacted_issue_ids.include?(pull_request.issue.id) }
        .sort_by { |i| i[column.content_sort_key] }
        .map(&:memex_column_hash)
    when MemexProjectColumn::PARENT_ISSUE_COLUMN_NAME
      return unless parent_issue_relation = public_send(column.special_type_association)
      return if redacted_issue_ids.include?(parent_issue_relation.source_issue_id)
      parent_issue_relation.source&.memex_column_hash
    when MemexProjectColumn::SUB_ISSUES_PROGRESS_COLUMN_NAME
      public_send(column.special_type_association)&.memex_column_hash&.transform_keys { |key| key.to_s.camelize(:lower).to_sym }
    when MemexProjectColumn::TITLE_COLUMN_NAME
      memex_denormalized_title_value
    end
  end

  # Direct use of this method is discouraged!
  # Use `MemexProjectItem#memex_special_type_column_value` instead.
  #
  # This method is used to generate CSV exports for the Memex project board,
  # as part of `MemexProjectItem#memex_special_type_column_value`. which is the reason its direct use is discouraged.
  #
  # Implements MemexProjectItem::Content#memex_special_type_csv_column_value.
  #
  # Returns CSV compatible string
  def memex_special_type_csv_column_value(column, require_prefilled_associations: true, redacted_issue_ids: [])
    return [] if column.reviewers? # issues by definition do not have reviewers
    ensure_preloaded_association!(column) if require_prefilled_associations

    data_type = column.data_type.to_sym

    case data_type
    when :assignees, :labels
      public_send(column.special_type_association)
        .sort_by { |i| i[column.content_sort_key]&.downcase }
        .map(&:csv_column_value).join(", ")
    when :milestone, :repository, :issue_type
      public_send(column.special_type_association)&.csv_column_value
    when :linked_pull_requests
      public_send(column.special_type_association)
        .map(&:pull_request)
        .reject { |pull_request| redacted_issue_ids.include?(pull_request.issue.id) }
        .sort_by { |i| i[column.content_sort_key] }
        .map(&:csv_column_value).join(", ")
    when :parent_issue
      return unless parent_issue_relation = public_send(column.special_type_association)
      return if redacted_issue_ids.include?(parent_issue_relation.source_issue_id)
      parent_issue_relation.source&.csv_column_value
    when :sub_issues_progress
      public_send(column.special_type_association)&.csv_column_value
    when :title
      title
    end
  end

  # Implements MemexProjectItem::Content#memex_denormalized_title_value.
  def memex_denormalized_title_value
    result = {
      title: {
        raw: title,
        html: GitHub::Goomba::TitleMarkdownFilter.call(title)
      },
      number: number,
      issueId: id,
      state: state.to_s,
      url: id_based_url,
    }

    unless pull_request_id
      # If the suggestion isn't a PR, include the issue state_reason
      result = result.merge({ stateReason: state_reason&.to_s })
    end

    result
  end

  # Implements MemexProjectItem::Content#can_have_milestone?
  def can_have_milestone?
    true
  end

  # Implements MemexProjectItem::Content#memex_denormalized_milestone_value.
  def memex_denormalized_milestone_value
    milestone&.memex_denormalized_value
  end

  def to_issue_authorizable
    Issue::Authorizable.new(id, repository_id)
  end

  def touch_memex_project_items
    if self.pull_request?
      TouchMemexProjectItemsJob.perform_later(self.pull_request)
    else
      TouchMemexProjectItemsJob.perform_later(self)
    end
  end

  sig { override.returns(Elastomer::Interfaces::Document::MemexProjectItem::Content) }
  def memex_content_elasticsearch_document
    Elastomer::Interfaces::Document::MemexProjectItem::Content.new(
      id: T.must(id),
      type: Elastomer::Interfaces::Document::MemexProjectItem::ContentType::Issue,
      state: Elastomer::Interfaces::Document::MemexProjectItem::IssueState.deserialize(state.to_s),
      state_reason: state_reason ? Elastomer::Interfaces::Document::MemexProjectItem::IssueStateReason.deserialize(state_reason.to_s) : nil,
      is_draft: false,
      number: number,
      repository_id: repository_id,
      user_id: user_id,
      closed_at: closed_at&.iso8601,
      created_at: created_at&.iso8601,
    )
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def memex_column_hash
    {
      id: id,
      globalRelayId: global_relay_id,
      number: number,
      state: state.to_s,
      stateReason: state_reason.to_s,
      title: title,
      titleHtml: GitHub::Goomba::TitleMarkdownFilter.call(title),
      repository: repository&.name,
      owner: repository&.owner&.display_login,
      nwoReference: name_with_display_owner_reference,
      url: url,
      subIssueList: sub_issue_list&.to_h&.transform_keys { |key| key.to_s.camelize(:lower) },
      updatedAt: updated_at&.utc.iso8601
    }
  end
  alias_method :group_metadata, :memex_column_hash
  alias_method :slice_metadata, :memex_column_hash

  def redacted_memex_column_hash
    redacted_title = "You can't see this issue"
    {
      id: id,
      globalRelayId: global_relay_id,
      number: number,
      state: nil,
      stateReason: nil,
      title: redacted_title,
      titleHtml: redacted_title,
      repository: nil,
      owner: nil,
      nwoReference: "#{repository_id}##{number}",
      url: nil,
      subIssueList: nil,
      updatedAt: nil
    }
  end
  alias_method :redacted_metadata, :redacted_memex_column_hash

  private

  def ensure_preloaded_association!(memex_column)
    if Rails.env.test? &&
        memex_column.special_type_association &&
        !self.association(memex_column.special_type_association).loaded?

      raise AssociationRefused.new(memex_column.special_type_association)
    end
  end

  # Used only in tests to report that a proposed operation is not efficient.
  class AssociationRefused < StandardError
    def initialize(association)
      super(
        "Refusing to map over unloaded :#{association} association: " +
        "please prefill this association efficiently before calling this method."
      )
    end
  end

  def track_execution_time(tags)
    timer = Timer.start
    result = yield
    owner = T.must(repository&.owner)

    GitHub.dogstats.distribution("sidebar_accessible_memexes.dist.time", timer.elapsed_ms, tags: tags << "owner_type:#{owner.type}")
    result
  end
end
