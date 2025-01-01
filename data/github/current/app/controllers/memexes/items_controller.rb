# typed: true
# frozen_string_literal: true

class Memexes::ItemsController < Memexes::Controller
  include Memexes::ItemsController::ResponseDependency
  include ApplicationController::VerifiedFetchDependency
  include BaseHelpers::Helpers

  READONLY_CONTROLLER_ACTIONS = [
    :edit_form, # edit_form can be rendered as a readonly form
    :legacy_archived_items,
    :get,
    :tracked_by_parent,
    :index,
  ].freeze

  # Actions taken on a specific project item or series of project items
  ITEM_CONTROLLER_ACTIONS = [
    :edit_form,
    :get,
    :suggested_milestones,
    :update,
    :destroy,
    :convert_to_issue
  ].freeze

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::ItemsController#create",
    "Memexes::ItemsController#update",
    "Memexes::ItemsController#destroy",
    "Memexes::ItemsController#convert_to_issue",
    "Memexes::ItemsController#reindex"
  ].freeze

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast

  # This validation needs to run before anything accesses this_item or these_items
  before_action :require_valid_project_item_params, only: ITEM_CONTROLLER_ACTIONS

  before_action :login_required, except: [:edit_form, :legacy_archived_items, :get, :index]
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :require_memex_resync_index_feature_enabled, only: [:reindex]
  before_action :require_memex_paginated_archive_or_memex_table_without_limits_feature_enabled, only: [:index, :reindex]
  before_action :user_has_admin_access, only: [:reindex]
  before_action :user_has_write_access, except: READONLY_CONTROLLER_ACTIONS
  before_action :user_has_read_access, only: READONLY_CONTROLLER_ACTIONS
  before_action :require_valid_grouping_and_slicing_parameters, only: [:index]
  before_action :require_verified_email, except: READONLY_CONTROLLER_ACTIONS
  before_action :require_priorities, only: [:create, :update]
  before_action :require_valid_content_parameters, only: [:create]
  before_action :require_this_repository_for_non_draft_issue, only: [:create]
  before_action :require_this_content, only: [:create]
  before_action :require_these_items, only: [:update, :edit_form, :get]
  before_action :require_these_items_writable, only: [:update]
  before_action :require_content_deletable, only: [:destroy]
  before_action :require_valid_update_for_draft_issue, only: [:update], if: :any_draft_issues?
  before_action :require_non_draft_issue_these_items, only: [:suggested_milestones]
  before_action :require_actor_can_read_issue_suggestions, only: [:suggested_milestones], unless: :any_draft_issues?
  before_action :require_actor_can_update_title, only: [:update]
  before_action :require_actor_can_add_assignees, only: [:update], unless: proc {
    T.bind(self, Memexes::ItemsController)
    %w[update].include?(action_name) && !column_types_to_update.include?(:assignees)
  }
  before_action :require_actor_can_add_labels, only: [:update]
  before_action :require_actor_can_add_milestones, only: [:update, :suggested_milestones]
  before_action :require_actor_can_add_issue_types, only: [:update,]
  before_action :require_actor_can_add_sub_issues, only: [:update]
  before_action :require_actor_can_set_tracked_by, only: [:update,]
  before_action :require_previous_item, only: [:update]
  before_action :require_valid_item_create_column_value_parameters, only: [:create]
  before_action :require_valid_item_create_previous_item, only: [:create]
  before_action :require_valid_item_update_column_value_parameters, only: [:update]
  before_action :require_repository_has_issues, only: [:update]

  before_action :require_valid_repository_owner, only: [:convert_to_issue]

  before_action :require_non_archived_these_items, only: [:update]

  before_action :set_client_uid
  before_action :set_cache_control_no_store
  after_action :instrument_update_event, only: [:update]

  allow_verified_fetch only: [:create, :update, :destroy, :convert_to_issue, :reindex]

  DEFAULT_ARCHIVED_ITEMS_PAGE_SIZE = 500
  MAX_ARCHIVED_ITEMS_PAGE_SIZE = 10000

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:create]
  depends_on_clusters ApplicationRecord::Spokes, only: [:create], optional: true

  def create
    item = this_memex.build_item(
      creator: current_user,
      draft_issue_title: create_memex_item_params.dig(:content, :title),
      issue_or_pull: this_content,
      column_data: {}
    )

    if item.valid?
      prioritization_options = {}
      if create_memex_item_params.has_key?(:previous_memex_project_item_id)
        prioritization_options = previous_item_for_create ? { after: previous_item_for_create } : { position: :top }
      end

      if !item.draft_issue?
        # after we verify that a valid item can be created, we need to make sure the current user
        # has write access to the repository if they're updating any repository fields.
        item_content = item_content(item)
        column_list_for_item_creation.each do |c|
          column_data_type = c[:column]&.data_type&.to_sym
          next if !c[:column]&.special_type?
          case column_data_type
          when :assignees
            return render_json_error(error: "User does not have permission to assign users to this item", status: :forbidden, code: "Forbidden") unless item_content.assignable_by?(actor: current_user)
          when :milestone
            return render_json_error(error: "User does not have permission to set milestones to this item", status: :forbidden, code: "Forbidden") unless item_content.can_set_milestone?(current_user)
          when :labels
            return render_json_error(error: "User does not have permission to label items to this item", status: :forbidden, code: "Forbidden") unless item_content.labelable_by?(actor: current_user)
          when :issue_type
            return render_json_error(error: "User does not have permission to set issue type on this item", status: :forbidden, code: "Forbidden") unless item_content.can_set_type?(actor: current_user)
          when :tracked_by
            add, remove = item.diff_tracked_by_values(item_content, c[:value], current_user)
            return render_json_error(error: "User does not have permission to set tracked by to this item or the parent item", status: :forbidden, code: "Forbidden") unless item_content.can_set_tracked_by?(actor: current_user, parent_issues: add + remove)
          when :parent_issue
            return render_json_error(error: "User does not have permission to add sub-issues to this item", status: :forbidden, code: "Forbidden") unless item_content.can_add_sub_issue?(actor: current_user, parent_issue_id: c[:value])
          else
            return render_json_error(error: "Cannot create an item with pre-populated #{column_data_type} value", status: :forbidden, code: "Forbidden")
          end
        end
      end

      # Because we were passing the first column data to be built with the item on creation,
      # we do that here now. Still not sure why we need to.
      first_column_data = column_list_for_item_creation.first || {}
      if first_column_data[:column] && T.must(first_column_data[:column]).name != MemexProjectColumn::MILESTONE_COLUMN_NAME
        item.memex_project_column_values.build(
          memex_project_column: first_column_data[:column],
          value: first_column_data[:value],
          creator: current_user
        )
      # adding a milestone requires additional info for the JsonValueValidator, so we
      # confirm if the column is a milestone column and the item supports milestones and then find the milestone
      elsif first_column_data[:column] && T.must(first_column_data[:column]).name == MemexProjectColumn::MILESTONE_COLUMN_NAME && item.can_have_milestone?
        milestone = item.repository.milestones.find_by(id: first_column_data[:value])
        if milestone.present?
          column_value = item.memex_project_column_values.find { |val| val.memex_project_column_data_type == MemexProjectColumn.data_types[:milestone] }
          item.memex_project_column_values.delete(column_value) if column_value.present?
          item.memex_project_column_values.build(
            memex_project_column: first_column_data[:column],
            value: first_column_data[:value],
            creator: current_user,
            json_value: {
              type: T.must(first_column_data[:column]).name,
              value: milestone.memex_column_hash
            }
          )
        end
      end

      this_memex.save_with_priority!(item, **prioritization_options)

    # handle "already exists in this project" if we're trying to update column values
    elsif item.errors.of_kind?(:content_id, :taken) && !create_memex_item_params[:memex_project_column_values].blank?
      project_item = this_memex.memex_project_items.find_by(content_id: item.content_id, content_type: item.content_type)

      create_memex_item_params[:memex_project_column_values].each do |column_data|
        column_id, new_value = column_data.values_at(:memex_project_column_id, :value)
        status, errors = project_item.set_column_value_if_found(column_id, new_value, current_user)
        return render(json: { errors: }, status:) unless status == :ok
      end

      columns = remove_excluded_columns(project_item.memex_project.memex_project_columns).to_a
      serialized_item = serialize_items([project_item], columns, cap_filter)[:serialized_items].first

      return render(json: { memexProjectItem: serialized_item })
    end

    if item.persisted?
      item.queue_set_column_values(column_list_for_item_creation, current_user)
      serialized_item, prefilled_associations = serialize_items([item], item_create_required_columns, cap_filter).values_at(:serialized_items, :prefilled_associations)
      memex_project_item = serialized_item.first
      memex_project_column = prefilled_associations&.partial_failures&.map do |partial_failure|
        { id: partial_failure[:memexProjectColumn], partialFailures: partial_failure }
      end
      return render(
        json: {
          memexProjectItem: memex_project_item,
          memexProjectColumn: memex_project_column,
        },
        status: :created
      )
    end

    # Determine if the MemexProjectItem could not be created as it already exists in the MemexProject. If it is
    # archived, the desired behavior is to unarchive it.
    item_duplicated = item.errors.of_kind?(:content_id, :taken)

    # Before attempting to unarchive the original MemexProjectItem that was duplicated, ensure that the request did
    # not include any column values that would overwrite the original MemexProjectItem unintentionally.
    attempt_unarchiving_duplicated_item = item_duplicated && column_list_for_item_creation.blank?
    archived_item = if attempt_unarchiving_duplicated_item
      MemexProjectItem.where(
        repository_id: item.content.repository_id,
        content: item.content,
        memex_project: this_memex,
      ).archived.first
    end

    if archived_item && archived_item.unarchive!
      memex_project_item = serialize_items([archived_item], item_create_required_columns, cap_filter)[:serialized_items].first

      render(
        json: { memexProjectItem: memex_project_item },
        status: :ok
      )
    else
      render(json: { errors: item.errors.full_messages }, status: :unprocessable_entity)
    end
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:get]
  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes, only: [:get], optional: true

  def get # rubocop:todo GitHub/UseRestfulActions
    item = serialize_items([this_item], this_memex_columns, cap_filter)[:serialized_items].first
    render(json: { memexProjectItem: item })
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:index]
  depends_on_clusters ApplicationRecord::Mysql2, only: [:index], optional: true

  def index
    response = Search::Responses::MemexItemsApiResponse.build(
      query: index_search_query,
      serializer: ->(items) do
        serialize_items(items, columns_to_serialize, cap_filter, from_paginated_context: true)[:serialized_items]
      end
    )

    GlobalInstrumenter.instrument("projects_without_limits_engagement", { actor: current_user&.id, project: this_memex.id })

    render(json: response.to_hash)
  rescue Search::Queries::CursorPagination::ParameterError => e
    render_json_error(error: e.message, status: :unprocessable_entity)
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:update]
  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Ballast,
    ApplicationRecord::Permissions,
    ApplicationRecord::Spokes, only: [:update], optional: true

  def update
    success = if updating_item_priority? && updating_column_value?
      this_item.move(
        column_value_updates: column_list_for_item_update,
        user: current_user,
        project_view: this_memex_view,
        prioritization_options:
      )
    elsif updating_item_priority?
      this_item.update_priority(prioritization_options)
    elsif updating_column_value?
      this_item.update_column_values(column_list_for_item_update, current_user)
    else
      true
    end

    if success
      columns = updating_item_priority? && !updating_column_value? ? [] : this_memex_columns
      _, redactor = prefill_memex_item_associations([this_item], columns: columns)
      render(json: { memexProjectItem: this_item.to_hash(columns: columns, redacted_issue_ids: redactor.redacted_issue_ids) })
    else
      render(json: { errors: this_item.errors.full_messages }, status: :unprocessable_entity)
    end
  rescue GitHub::Prioritizable::Context::LockedForRebalance, GitHub::Prioritizable::SBT::Context::LockedForRebalance => e
    GitHub.logger.info(
      "code.namespace": self.class.name,
      "code.function": "update",
      "error.message": e.message,
      "gh.memexes.items_controller.update.item.id": this_item.id,
      "gh.memexes.items_controller.update.project.id": this_item.memex_project_id,
    )
    render_json_error(
      error: "This project is undergoing maintenance.",
      status: :service_unavailable
    )
  end

  class NoProjectItemsFoundError < StandardError; end
  class BulkUpdatesFailedError < StandardError; end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:destroy]
  depends_on_clusters ApplicationRecord::Permissions,
    ApplicationRecord::Spokes, only: [:destroy], optional: true

  def destroy
    memex_project_item_ids = destroy_memex_items_params[:memex_project_item_ids]&.uniq || []

    if destroy_memex_items_params[:q] &&
      memex_project_item_ids.none? &&
      (memex_table_without_limits_enabled? || memex_paginated_archive_enabled?)

      query_result = destroy_search_query.execute

      if query_result.has_next_page
        items_scope, _ = scope_options(destroy_memex_items_params)
        job_status = JobStatus.create
        MemexProjectItemQueryJob.perform_later(
          job_id: job_status.id,
          current_user_id: current_user,
          memex_id: this_memex.id,
          query_string: destroy_memex_items_params[:q],
          action_job_klass: MemexDestroyItemsJob,
          items_scope: items_scope.serialize
        )
        return render(
          json: { job: { url: job_status_url(job_status.id) } },
          status: :ok
        )
      end

      memex_project_item_ids = query_result.map { |r| r.dig("_source", "database_id") }
    end

    if memex_project_item_ids.size > MemexProjectItem::DELETE_IN_FOREGROUND_LIMIT
      job_status = this_memex.destroy_project_items_later(viewer: current_user, item_ids: memex_project_item_ids)
      return render(
        json: { job: { url: job_status_url(job_status.id) } },
        status: :ok
      )
    end

    old_items = this_memex.memex_project_items.where(id: memex_project_item_ids).destroy_all
    return head(:unprocessable_entity) unless old_items.any?
    head(old_items.all?(&:destroyed?) ? :no_content : :unprocessable_entity)
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:convert_to_issue]
  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Spokes, only: [:convert_to_issue], optional: true

  def convert_to_issue # rubocop:todo GitHub/UseRestfulActions
    warnings = nil
    begin
      warnings = MemexProjectItem::ConvertToIssue.call(
        memex_project_item: this_item,
        actor: current_user,
        repository: convert_to_issue_repository,
      )
    rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordNotDestroyed => e
      Failbot.report e
      Storage::UserAssetTransfer::DraftToRepositoryTransferRollback.rollback_to(this_memex, current_user, this_item.content.body)
      return render_json_error(error: "Unable to create new issue from draft issue", status: :unprocessable_entity)
    rescue MemexProjectItem::ConvertToIssue::Error => e
      return render_json_error(error: e.message, status: :unprocessable_entity)
    rescue Storage::UserAssetTransfer::Transfer::TransferError => e
      return render_json_error(error: "Unable to transfer assets to new issue. Please try again.", status: :unprocessable_entity)
    rescue ActiveRecord::RecordInvalid => e
      if e.message.include?("was submitted too quickly")
        # unable to use 429 as that status code results in a re-direct to a 429 status page
        return render_json_error(error: "Unable to create new issue. Please try again later.", status: :bad_request)
      end
    end

    columns = this_memex_columns
    _, redactor = prefill_memex_item_associations([this_item], columns: columns)
    json = { memexProjectItem: this_item.to_hash(columns: columns, redacted_issue_ids: redactor.redacted_issue_ids) }
    json[:warnings] = warnings.to_hash if warnings.present?

    render(json: json)
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:suggested_milestones]
  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes, only: [:suggested_milestones], optional: true

  def suggested_milestones # rubocop:todo GitHub/UseRestfulActions
    suggestions = get_suggestions("milestones", item_content)
    render(json: { suggestions: suggestions })
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:edit_form]
  depends_on_clusters ApplicationRecord::Mysql2, only: [:edit_form], optional: true

  def edit_form # rubocop:todo GitHub/UseRestfulActions
    render Memex::EditFormComponent.new(
      memex: this_memex,
      item: this_item,
      viewer_can_write: this_memex.viewer_can_write?(current_user)
    ), layout: false
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:legacy_archived_items]
  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast, only: [:legacy_archived_items], optional: true

  # REST API - Get a limited set of archived items, including archived at/by and total archive count.
  # Returns items ordered most recently archived first, for the requested columns and page size.
  #
  # This endpoint has been deprecated ahead of the new API planned in
  # https://github.com/github/projects-backend/issues/119. It will soon be removed.
  def legacy_archived_items # rubocop:todo GitHub/UseRestfulActions
    total_archived_items_count = [this_memex.memex_project_items.archived.count, MemexProjectItem::ARCHIVED_ITEM_LIMIT].min

    archived_items = this_memex.memex_project_items
      .archived
      .order(archived_at: :desc)
      .limit(per_page || MAX_ARCHIVED_ITEMS_PAGE_SIZE)

    columns = this_memex_view_visible_columns.present? ? this_memex_view_visible_columns : [this_memex.columns.find(&:title?)]
    serialized_items = serialize_items(archived_items, columns, cap_filter)[:serialized_items]

    render(json: {
      memexProjectItems: serialized_items,
      totalCount: total_archived_items_count
    })
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:legacy_archive_status]
  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes, only: [:legacy_archive_status], optional: true

  # REST API - Get status of the archive by comparing the total number of archived items to the archive limit.
  # Returns the number of archived items, the archive limit, and whether archive is full.
  #
  # This endpoint has been deprecated ahead of support for an unlimited archive via
  # https://github.com/github/planning-tracking/issues/1594. It will soon be removed.
  def legacy_archive_status # rubocop:todo GitHub/UseRestfulActions
    num_archived_items = this_memex.memex_project_items.archived.count

    render(json: {
      isArchiveFull: num_archived_items >= this_memex.archived_items_limit,
      totalCount: num_archived_items,
      archiveLimit: this_memex.archived_items_limit
    })
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:tracked_by_parent]

  # REST API - Gets child issues and parent completion information by the parent issue id
  # Excludes child issues the current user does not have access to or issues already present in the Memex project
  def tracked_by_parent # rubocop:todo GitHub/UseRestfulActions
    return head(:unprocessable_entity) unless tracks_and_tracked_by_enabled?

    parent_id = underscored_params[:issue_id]
    return render_404 unless parent_id.present?

    parent_issue = Issue.find_by(id: parent_id)
    return render_404 unless parent_issue.present?
    return render_404 unless parent_issue.repository&.readable_by?(current_user)

    children, parent_completion = MemexProjectItem.children_for_parent(parent_issue)
    return head(:unprocessable_entity) if !children.present? || children.empty?

    # Get list of children not yet in a project for users to import these items
    items_in_project = this_memex.memex_project_items.reject(&:draft_issue?).pluck(:content_id).index_with(true)
    issues = children.reject { |issue| items_in_project.key?(issue.issue_id) }
    redactor = TasklistBlocks::Redactor.new(
      viewer: current_user,
      issues: issues,
      cap_filter: cap_filter
    )

    accessible_issues = redactor.issues.reject { |issue| issue.is_a?(TasklistBlocks::RedactedIssue) }
    json = { count: accessible_issues.length, items: accessible_issues.map(&:to_h), parentCompletion: parent_completion || {} }
      .deep_transform_keys { |key| key.to_s.camelize(:lower) }.as_json

    render(json: json)
  end

  # REST API - Reindexes items in Elasticsearch for a given Memex project.
  def reindex # rubocop:todo GitHub/UseRestfulActions
    job_status = this_memex.queue_reindex_items

    render(
      json: { job: { url: job_status_url(job_status.id) } },
      status: :ok
    )
  end

  private

  def require_memex_resync_index_feature_enabled
    render_404 unless memex_resync_index_enabled?
  end

  def require_memex_paginated_archive_or_memex_table_without_limits_feature_enabled
    render_404 unless memex_paginated_archive_enabled? || memex_table_without_limits_enabled?
  end

  def per_page
    per_page = params[:per_page].to_i
    per_page = per_page.zero? ? DEFAULT_ARCHIVED_ITEMS_PAGE_SIZE : per_page
    per_page.clamp(1, MAX_ARCHIVED_ITEMS_PAGE_SIZE)
  end

  def this_memex_columns
    remove_excluded_columns(columns_to_serialize).to_a
  end

  def this_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return if create_memex_item_params[:content_type] == DraftIssue.name
    return @this_repository if defined?(@this_repository)
    @this_repository = super(repository_id: create_memex_item_params[:content][:repository_id])
  end

  def previous_item # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @previous_item if defined?(@previous_item)
    @previous_item = this_memex
      .memex_project_items
      .find_by(id: single_item_update_params[:previous_memex_project_item_id])
  end

  def previous_item_for_create # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @previous_item_for_create if defined?(@previous_item_for_create)
    @previous_item_for_create = create_memex_item_params[:previous_memex_project_item_id].presence && this_memex
      .memex_project_items
      .find_by(id: create_memex_item_params[:previous_memex_project_item_id])
  end

  # The client sends a value param that can be of many shapes/classes. This
  # attempts to coerce the value that comes in into something that strong_params
  # will not throw on.
  def value_param_type_value(param = underscored_params[:memex_project_column_values]&.first)
    case param&.fetch(:value, nil)
    when String then :value
    when Numeric then :value
    when Hash then { value: {} }
    when Array then { value: [] }
    when ActionController::Parameters then { value: {} }
    when nil then :value
    end
  end

  def updating_column_value?
    update_multiple_column_value_params.present?
  end

  def updating_item_priority?
    single_item_update_params.has_key?(:previous_memex_project_item_id)
  end

  def prioritization_options
    previous_item ? { after: previous_item } : { position: :top }
  end

  def destroy_memex_items_params
    underscored_params.permit(:org, :user_id, :memex_number, :memex_id, :q, :scope, memex_project_item_ids: [])
  end

  def convert_to_issue_params
    underscored_params.permit(:org, :memex_number, :memex_id, :memex_project_item_id, :repository_id)
  end

  def require_not_draft_issue
    these_items.each do |item|
      if item&.draft_issue?
        render_json_error(error: "A content type of Issue or PullRequest is required", status: :unprocessable_entity)
      end
    end
  end

  def require_repository_has_issues
    return unless [:assignees, :labels, :milestone].intersect?(column_types_to_update)
    require_these_items_have_issues_enabled
  end

  def convert_to_issue_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @convert_to_issue_repository if defined?(@convert_to_issue_repository)
    repo = Repository.find_by(id: convert_to_issue_params[:repository_id])
    @convert_to_issue_repository = cap_filter.authorized_resources(repo)&.last
  end

  def require_valid_repository_owner
    return if convert_to_issue_repository&.owner == memex_owner
    return if convert_to_issue_repository&.writable_by?(current_user)

    render_json_error(error: "Repository is not owned by @#{memex_owner} or writable by @#{current_user}", status: :unprocessable_entity)
  end

  def require_actor_can_add_labels
    return if (action_name == "update") && !column_types_to_update.include?(:labels)
    require_these_items_labelable
  end

  def require_actor_can_add_milestones
    return if (action_name == "update") && !column_types_to_update.include?(:milestone)
    require_these_items_milestone_settable
  end

  def require_actor_can_add_issue_types
    return if !column_types_to_update.include?(:issue_type)

    require_these_items_issue_type_settable
  end

  # This hook is a bit different than most, as it verifies that the actor can
  # writes to the parent issue to be applied, rather than the current memex item
  def require_actor_can_add_sub_issues
    return unless column_types_to_update.include?(:parent_issue)

    param = update_multiple_column_value_params&.first
    return unless param.present?

    require_these_items_can_add_sub_issues(param[:value])
  end

  def require_actor_can_set_tracked_by
    return if (action_name == "update") && !column_types_to_update.include?(:tracked_by)
    param = update_multiple_column_value_params&.first
    return unless param
    require_these_items_can_set_tracked_by(param[:value])
  end

  def require_content_deletable
    # project admins should always be able to delete items
    # see https://github.com/github/memex/issues/11863#issuecomment-1263822223
    return if this_memex.viewer_is_admin?(current_user)
    memex_project_item_ids = destroy_memex_items_params[:memex_project_item_ids].uniq

    begin
      items = this_memex
        .memex_project_items
        .includes(:content)
        .find(memex_project_item_ids)
    rescue ActiveRecord::RecordNotFound
      return head(:unprocessable_entity)
    end

    result_promises = items.map do |item|
      issue = item_content(item)
      # draft issues are writable by anyone with project write access
      # issues should be removable from a project by anyone who can read them
      # and has project write access (which is checked before this method by user_has_write_access)
      # see https://github.com/github/memex/issues/11863#issuecomment-1263822223
      # Also allow deletion of an invalid item where its nil issue was previously destroyed but the item was not automatically removed.
      # See customer issue and related Sentry errors at https://github.com/github/memex/issues/18059
      issue.is_a?(DraftIssue) || issue.nil? || issue.async_readable_by?(current_user)
    end

    results = Promise.all(result_promises).sync

    if results.any?(false)
      render_json_error(error: "User does not have permission to delete specified items", status: :forbidden, code: "Forbidden")
    end
  end

  def require_priorities
    return if single_item_update_request? && !updating_item_priority?

    if this_memex.memex_project_items.exists?(virtual_priority: nil)
      this_memex.rebalance(association: :memex_project_items)
      render_json_error(error: "Sorry, something went wrong. Please try again.", status: :service_unavailable)
    end
  end

  def require_valid_item_create_previous_item
    return unless create_memex_item_params.has_key?(:previous_memex_project_item_id)
    return unless create_memex_item_params[:previous_memex_project_item_id].present?
    render_404 unless previous_item_for_create
  end

  def require_previous_item
    return unless updating_item_priority?
    return unless single_item_update_params[:previous_memex_project_item_id].present?
    render_404 unless previous_item
  end

  def validate_item_creation_with_multiple_columns
    return {
      error: "You have exceeded the maximum column values for this request",
      status: :unprocessable_entity
    } if create_multiple_column_value_params.length > MemexProject::COLUMN_LIMIT

    { error: "Column(s) not found", status: :not_found } unless column_list_for_item_creation.length > 0
  end

  def require_valid_item_create_column_value_parameters
    return if create_multiple_column_value_params.blank?
    invalid_columns = validate_item_creation_with_multiple_columns
    if invalid_columns
      render_json_error(error: invalid_columns[:error], status: invalid_columns[:status])
      return
    end

    error = column_list_for_item_creation
      .map { |column_data| validate_column_value_params(T.must(column_data[:column]), column_data[:value]) }
      .compact

    render_json_error(
      error: error,
      status: :unprocessable_entity
    ) unless error.empty?
  end

  def require_valid_item_update_column_value_parameters
    return if update_multiple_column_value_params.blank?

    invalid_columns = validate_item_update_with_multiple_columns
    if invalid_columns
      render_json_error(error: invalid_columns[:error], status: invalid_columns[:status])
      return
    end

    error = column_list_for_item_update
      .map { |column_data| validate_column_value_params(T.must(column_data[:column]), column_data[:value]) }
      .compact

    if error.present?
      render_json_error(
        error: error,
        status: :unprocessable_entity
      )
      return
    end

    if single_item_update_request?
      single_item_update_params[:memex_project_column_values]
    elsif bulk_item_update_request?
      bulk_item_update_params[:memex_project_column_values]
    end
  end

  def require_valid_grouping_and_slicing_parameters
    grouped_field_id, group_value = memex_primary_group_params
    secondary_grouped_field_id, secondary_group_value = memex_secondary_group_params
    invalid_primary = group_value.present? && grouped_field_id.blank?
    invalid_secondary = secondary_group_value.present? && secondary_grouped_field_id.blank?
    if invalid_primary || invalid_secondary
      return render_json_error(
        error: "groupedBy[value] must be used in combination with groupedBy[columnId]",
        status: :unprocessable_entity
      )
    end

    sliced_field_id, slice_value = index_slicing_params
    if slice_value.present? && sliced_field_id.blank?
      return render_json_error(
        error: "slicesdBy[value] must be used in combination with slicedBy[columnId]",
        status: :unprocessable_entity
      )
    end

    nil
  end

  sig { returns([T.nilable(Integer), T.nilable(String), T.nilable(String)]) }
  memoize private def memex_primary_group_params
    board_view_request = memex_group_params[:vertical].present?
    params = board_view_request ? memex_group_params[:vertical] : memex_group_params[:horizontal]
    grouped_field_id, group_value = params.map(&:presence)
    [grouped_field_id, group_value, underscored_params[:after]]
  end

  sig { returns([T.nilable(Integer), T.nilable(String), T.nilable(String)]) }
  memoize private def memex_secondary_group_params
    return [nil, nil, nil] unless current_user&.feature_enabled?(:memex_mwl_swimlanes)
    return [nil, nil, nil] unless memex_group_params[:vertical].present?
    secondary_grouped_field_id, secondary_group_value = memex_group_params[:horizontal].map(&:presence)
    [secondary_grouped_field_id, secondary_group_value, underscored_params[:secondary_after]]
  end

  sig { returns([T.nilable(Integer), T.nilable(String)]) }
  memoize private def index_slicing_params
    sliced_field_id, slice_value = memex_slice_params.map(&:presence)
    [sliced_field_id, slice_value]
  end

  def log(msg, **kwargs)
    GitHub.logger.info(msg, {
      "code.namespace": "Memexes::ItemsController",
      "gh.user.id": current_user.id,
      "gh.memex.project.id": this_memex&.id,
      "gh.memex.owner.id": memex_owner.id,
    }.merge(kwargs))
  end

  def instrument_update_event
    return unless params.has_key?(:ui)
    return unless logged_in?

    GlobalInstrumenter.instrument "memex_event", {
      actor: current_user,
      memex_project: this_item.memex_project,
      memex_project_item: this_item,
      memex_project_column: T.must(column_list_for_item_update.first)[:column], # todo Support tracking multiple columns for a single item
      performed_at: Time.current,
      ui: params[:ui],
      name: "item_edit"
    }
  end

  def index_search_query
    items_scope, default_sort = scope_options
    sort = memex_sort_params.presence || default_sort
    query = underscored_params[:q].to_s
    slice_by, slice_value = index_slicing_params
    index_search_query_grouping_options => { group_value_filters:, grouping_options: }

    Search::Queries::MemexProjectItemQuery.new(
      project: this_memex,
      viewer: current_user,
      cap_filter: cap_filter,
      items_scope:,
      query:,
      first: underscored_params[:first]&.to_i,
      after: underscored_params[:after],
      last: underscored_params[:last]&.to_i,
      before: underscored_params[:before],
      sort:,
      group_value_filters:,
      grouping_options:,
      slice_by:,
      slice_value:,
      include_empty_slices: true,
      include_slice_metadata: true,
    )
  end

  # Returns options for one of two possible, but mutually exclusive requests that the client might make:
  #
  # 1. A query for a page of items within a particular group, in which case this method should a hash with a non-nil
  #    `group_value_filter` value and a nil `grouping_options` value.
  # 2. A query for a page of groups, in which case this method should return a hash with a nil `group_value_filter`
  #    value and a and non-nil `grouping_options` value.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  private def index_search_query_grouping_options
    group_value_filters = grouping_options = nil

    grouped_field_id, group_value, after = memex_primary_group_params
    secondary_grouped_field_id, secondary_group_value, secondary_after = memex_secondary_group_params
    board_view_request = memex_group_params[:vertical].present?

    missing_value_group_order = if board_view_request
      MemexProjectColumn::Groupable::MissingValueGroupOrder::First
    else
      MemexProjectColumn::Groupable::MissingValueGroupOrder::Last
    end

    if grouped_field_id.present? && group_value.present?
      group_value_filters = [MemexProjectColumn::Queryable::FieldValueFilter.new(
        field_object_or_id: grouped_field_id,
        field_value: group_value
      )]
    elsif grouped_field_id.present?
      secondary_grouping_options = if secondary_grouped_field_id.present?
        MemexProjectColumn::Groupable::Options.new(
          field_object_or_id: secondary_grouped_field_id,
          cursor: secondary_after,
          missing_value_group_order: MemexProjectColumn::Groupable::MissingValueGroupOrder::Last,
          include_empty_groups: false,
          include_group_metadata: true,
          allow_group_page_size_override: !memex_mwl_server_group_order_enabled?,
        )
      else
        nil
      end
      grouping_options = MemexProjectColumn::Groupable::Options.new(
        field_object_or_id: grouped_field_id,
        cursor: after,
        missing_value_group_order:,
        include_empty_groups: board_view_request,
        include_group_metadata: true,
        allow_group_page_size_override: !memex_mwl_server_group_order_enabled?,
        secondary_grouping_options:
      )
    end
    if group_value_filters.present? && secondary_group_value.present? && secondary_grouped_field_id.present?
      group_value_filters << MemexProjectColumn::Queryable::FieldValueFilter.new(
        field_object_or_id: secondary_grouped_field_id,
        field_value: secondary_group_value
      )
    end

    { group_value_filters:, grouping_options: }
  end

  def destroy_search_query
    items_scope, sort = scope_options(destroy_memex_items_params)
    Search::Queries::MemexProjectItemQuery.new(
      project: this_memex,
      viewer: current_user,
      items_scope: items_scope,
      query: destroy_memex_items_params[:q].to_s,
      sort: sort,
    )
  end

  # Retuns [MemexProjectItemsScope enum, default_sort] for the :scope param, if provided. Defaults to [Unarchived, []]
  def scope_options(params = underscored_params)
    default_scope = Search::Memex::Context::MemexProjectItemsScope::Unarchived
    default_sort = []
    item_scope = Search::Memex::Context::MemexProjectItemsScope.try_deserialize(params[:scope]&.to_sym) || default_scope
    sort = item_scope == Search::Memex::Context::MemexProjectItemsScope::Archived ? [{ archived_at: "desc" }] : default_sort
    [item_scope, sort]
  end

  # Returns the columns to serialize for the current request, limited by an optional field_ids param.
  # field_ids can be an array of column_ids or a JSON string of an array of column_ids.
  memoize def columns_to_serialize
    requested_columns = this_memex.columns
    if underscored_params[:field_ids]
      field_ids = underscored_params[:field_ids]
      begin
        # JSON parse field_ids (typical of JSON string in the URL param)
        field_ids = JSON.parse(field_ids) if field_ids.is_a?(String)
      rescue JSON::ParserError
        # nothing more to needed here since we check for array next anyway.
      end

      # field_ids should now be an array whether from a GET URL param or a POST body param
      if field_ids.is_a?(Array)
        field_ids = field_ids.map(&:to_s)
        requested_columns = requested_columns.filter do |column|
          field_ids.include?(column.synthetic_id.to_s)
        end
      end
    end
    requested_columns
  end
end
