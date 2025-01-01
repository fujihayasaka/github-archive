# typed: true
# frozen_string_literal: true

class Memexes::Items::BulkActionsController < Memexes::ItemsController
  # Skip these triggers that are inherited from Memexes::ItemsController because they apply to #create or #update
  # in that class, and aren't meant to apply to the endpoints of the same name in this controller:
  skip_before_action :require_previous_item
  skip_before_action :require_priorities
  skip_after_action :instrument_update_event

  before_action :ensure_items_specified_to_update, only: [:update]
  before_action :require_valid_content_parameters, only: [:create]
  before_action :require_this_repository_for_non_draft_issue, only: [:create]
  before_action :require_this_content, only: [:create]
  before_action :ensure_draft_issue_title_within_limit, only: [:create]

  after_action :instrument_update_bulk_event, only: [:update]

  allow_verified_fetch only: [:create, :update]

  MAX_BULK_ADD_SIZE = 50

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::Items::BulkActionsController#create",
  ].freeze

  depends_on_clusters ApplicationRecord::Repositories,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::IssuesPullRequests, only: [:create]
  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Spokes, only: [:create], optional: true

  def create
    filter = DraftIssueReferenceFilter.new(text: draft_issue_title, viewer: current_user, multi_refs: true)
    unless filter.references
      return render(json: { job: nil, notParsedContent: filter.non_reference_text })
    end

    job_status = this_memex.bulk_add_multiple_items(
      creator: current_user,
      issues_or_pulls: filter.references,
      memex_project_column_values: column_list_for_item_creation,
    )
    if job_status.nil?
      return render(json: { job: nil, reason: "The job was not created" }, status: :bad_request)
    end

    render json: {
      job: { url: job_status_url(job_status.id) },
      notParsedContent: "Could not parse: #{filter.non_reference_text}",
    }
  end

  def update
    job_status = MemexItemsBulkUpdateJob.create_job_status
    MemexItemsBulkUpdateJob.perform_later(job_id: job_status.id, item_ids: item_ids,
      params: bulk_item_update_params, memex_project: this_memex, user: current_user)

    # Keep in sync with BulkUpdateMemexItemsResponse in ui/packages/memex/src/client/api/memex-items/contracts.ts
    render json: { job: { url: job_status_url(job_status.id) }, totalUpdatedItems: 0 }
  end

  private

  memoize def draft_issue_title
    create_memex_item_params.dig(:content, :title)
  end

  def ensure_draft_issue_title_within_limit
    if draft_issue_title.scan(DraftIssueReferenceFilter.reference_patterns).size > MAX_BULK_ADD_SIZE
      render json: { job: nil, notParsedContent: "You can add max #{MAX_BULK_ADD_SIZE} items at a time" },
        status: :bad_request
    end
  end

  def ensure_items_specified_to_update
    if these_items.empty?
      render_json_error(error: "No items were specified to update.", status: :unprocessable_entity)
    end
  end

  def instrument_update_bulk_event
    return unless params.has_key?(:ui)
    return unless logged_in?

    GlobalInstrumenter.instrument "memex_event", {
      actor: current_user,
      memex_project: these_items[0].memex_project,
      memex_project_items: these_items,
      memex_project_column: T.must(column_list_for_item_update.first)[:column], # todo Support tracking multiple columns for a single item
      performed_at: Time.current,
      ui: params[:ui],
      name: "item_bulk_edit"
    }
  end
end
