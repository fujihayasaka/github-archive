# typed: true
# frozen_string_literal: true

class Memexes::Items::ArchiveController < Memexes::Controller
  include Memexes::ItemsController::ResponseDependency
  include ActionView::Helpers::NumberHelper
  include ApplicationController::VerifiedFetchDependency

  # cluster dependencies analysis will be enabled for these non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::Items::ArchiveController#create",
    "Memexes::Items::ArchiveController#update",
  ].freeze

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab

  before_action :login_required
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_write_access
  before_action :require_verified_email
  before_action :set_client_uid
  before_action :set_cache_control_no_store
  allow_verified_fetch only: [:create, :update]

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:create]

  def create
    memex_project_item_ids = archive_memex_items_params[:memex_project_item_ids].uniq
    if memex_project_item_ids.size > MemexProjectItem::ARCHIVE_IN_FOREGROUND_LIMIT
      return archive_job(memex_project_item_ids)
    end

    viewable_items, unviewable_items = ActiveRecord::Base.connected_to(role: :reading) do
      this_memex.partition_items_by_readability(current_user, memex_project_item_ids)
    end

    unviewable_items.each do |item|
      log("Unable to archive item due to insufficient permissions", "gh.memex.item.id": item.id)
    end

    archived_count = 0
    begin
      MemexProjectItem.transaction do
        viewable_items.each do |item|
          item.archive!
          archived_count += 1
        end
      end
    rescue ActiveRecord::RecordInvalid => error
      if error.record&.errors&.of_kind?(:base, :archive_limit_reached)
        return render_json_error(error: archive_error_message(memex_project_item_ids.length, archived_count),
          status: :unprocessable_entity)
      else
        return render_json_error(error: "Unable to archive items in project", status: :unprocessable_entity)
      end
    end

    head(:no_content)
  end

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:update]
  depends_on_clusters ApplicationRecord::Spokes, only: [:update], optional: true

  def update
    memex_project_item_ids = archive_memex_items_params[:memex_project_item_ids]&.uniq || []

    if archive_memex_items_params[:q] && memex_project_item_ids.none? && memex_paginated_archive_enabled?
      query_result = archived_items_search_query.execute

      if query_result.total + this_memex.memex_project_items.for_page_limit.count > this_memex.items_limit
        return render_json_error(error: "Unable to restore items, maximum number of items in project exceeded",
          status: :unprocessable_entity)
      end

      if query_result.has_next_page
        job_status = MemexProjectItemQueryJob.create_job_status
        MemexProjectItemQueryJob.perform_later(
          job_id: job_status.id,
          current_user_id: current_user,
          memex_id: this_memex.id,
          query_string: archive_memex_items_params[:q],
          action_job_klass: MemexUnarchiveItemsJob,
          items_scope: :archived,
          request_context: GitHub.context.to_hash,
        )
        return render(json: { job: { url: job_status_url(job_status.id) } }, status: :ok)
      end

      memex_project_item_ids = query_result.map { |r| r.dig("_source", "database_id") }
    end

    ActiveRecord::Base.connected_to(role: :reading) do
      @viewable_items, @unviewable_items = this_memex.partition_items_by_readability(current_user,
        memex_project_item_ids)
    end

    @unviewable_items.each do |item|
      log("Unable to unarchive item due to insufficient permissions", "gh.memex.item.id": item.id)
    end

    total_items = memex_project_item_ids.size + this_memex.memex_project_items.for_page_limit.count
    if total_items > this_memex.items_limit
      return render_json_error(error: "Unable to restore items, maximum number of items in project exceeded",
        status: :unprocessable_entity)
    end

    if memex_project_item_ids.size > MemexProjectItem::UNARCHIVE_IN_FOREGROUND_LIMIT
      job_status = this_memex.unarchive_project_items_later(viewer: current_user, item_ids: memex_project_item_ids)
      return render(json: { job: { url: job_status_url(job_status.id) } }, status: :ok)
    end

    begin
      MemexProjectItem.transaction do
        @viewable_items.each(&:unarchive!)
      end
    rescue ActiveRecord::RecordInvalid
      return render_json_error(error: "Unable to restore items in project", status: :unprocessable_entity)
    end

    head(:no_content)
  end

  private

  def archive_memex_items_params
    underscored_params.permit(:org, :user_id, :memex_number, :memex_id, :q, memex_project_item_ids: [])
  end

  def log(msg, **kwargs)
    GitHub.logger.info(msg, {
      "code.namespace": self.class.name,
      "code.function": __method__,
      "gh.user.id": current_user.id,
      "gh.memex.project.id": this_memex&.id,
      "gh.memex.owner.id": memex_owner.id,
    }.merge(kwargs))
  end

  def archive_job(memex_project_item_ids)
    # We don't check permissions here, only an exploiting user would try this and they don't need nice error messages.
    # Permissions are checked in the background job.
    remaining_space = this_memex.archived_items_limit - this_memex.memex_project_items.archived.count
    remaining_space = 0 if remaining_space < 0

    if memex_project_item_ids.count <= remaining_space
      job_status = this_memex.archive_job(viewer: current_user, items: memex_project_item_ids)
      return render(json: { job: { url: job_status_url(job_status.id) } }, status: :ok)
    end

    archive_limit_message = if remaining_space <= 0
      ". #{number_with_delimiter(this_memex.archived_items_limit)} items archive limit reached"
    else
      ", because only #{remaining_space} fit"
    end

    render_json_error(error: archive_error_message(memex_project_item_ids.count, remaining_space),
      status: :unprocessable_entity)
  end

  def archive_error_message(number_of_items_to_archive, remaining_space)
    archive_limit_message = if remaining_space <= 0
      ". #{number_with_delimiter(this_memex.archived_items_limit)} items archive limit reached"
    else
      ", because only #{remaining_space} fit"
    end

    "Unable to archive #{number_of_items_to_archive} #{"item".pluralize(number_of_items_to_archive)} in " \
      "project#{archive_limit_message}"
  end

  def serialize_items(items, columns)
    prefilled_associations = prefill_associations(items, columns)
    serializer = MemexProjectItemSerializer.new(
      viewer: current_user,
      memex: this_memex,
      items: items,
      columns: columns,
      prefilled_associations: prefilled_associations,
      cap_filter: cap_filter
    )
    serialized_items = serializer.result.items
    { serialized_items: serialized_items, prefilled_associations: prefilled_associations }
  end

  def require_memex_paginated_archive_feature_enabled
    render_404 unless memex_paginated_archive_enabled?
  end

  def archived_items_search_query
    Search::Queries::MemexProjectItemQuery.new(
      project: this_memex,
      viewer: current_user,
      cap_filter: cap_filter,
      items_scope: Search::Memex::Context::MemexProjectItemsScope::Archived,
      query: underscored_params[:q].to_s,
      sort: [{ archived_at: "desc" }],
      first: underscored_params[:first]&.to_i,
      after: underscored_params[:after],
    )
  end
end
