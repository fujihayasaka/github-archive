# typed: true
# frozen_string_literal: true

class MergeQueues::EntriesController < AbstractRepositoryController
  include MergeQueues::SharedControllerMethods
  include ControllerMethods::PullRequests

  before_action :merge_queue_required
  before_action :pull_request_required, only: [:create]
  before_action :require_xhr, only: [:create]
  before_action :content_authorization_required, only: [:create]
  before_action :entry_adminable_by_current_user_required, only: [:destroy, :update]

  include TimelineHelper
  include ShowPartial

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:index]

  def index
    render partial: "merge_queue/entries", locals: {
      entries: up_next_entries_for_display,
      merge_queue: merge_queue,
      page: current_page,
      state: params[:state],
    }
  end

  def destroy
    pull_request = entry.pull_request
    if merge_queue.dequeue(pull_request: pull_request, dequeuer: current_user)
      flash[:notice] = "Successfully removed PR ##{pull_request.number} \"#{pull_request.title}\"".truncate(100)
    else
      flash[:error] = "Failed to remove PR ##{pull_request.number} \"#{pull_request.title}\"".truncate(100)
    end

    respond_to do |format|
      format.html { redirect_to :back }
      format.json do
        message = flash[:error] || flash[:notice]
        flash.delete(:notice) # we don't want the success message to show up later after an unrelated page refresh
        render json: { message: message }, status: flash[:error] ? 500 : 200
      end
    end
  end

  def create
    entry = merge_queue
      .enqueue!(
        pull_request: pull_request,
        enqueuer: current_user,
        solo: params[:merge_method] == "solo",
        jump_queue: params[:merge_method] == "jump",
      )

    pull_node = PullRequest::ShowLoader.issue_node(pull_request, current_repository, current_user, cap_filter: cap_filter, pagination_params: { per_page: params[:timeline_per_page], timeline_since: helpers.discussion_last_modified_at&.iso8601 })
    # required for the issue timeline partial
    @pull = pull_request

    render_update_content_json({
      timeline: render_to_string(
        partial: "pull_requests/timeline",
        object: pull_request,
        formats: :html,
        locals: {
          pull_node: pull_node,
        },
      ),
      sidebar: render_to_string(
        partial: "pull_requests/sidebar",
        object: pull_request,
        formats: :html,
        locals: {
          pull_node: pull_node,
          pull: pull_request,
        },
      ),
      merging: render_to_string(
        partial: "pull_requests/merging",
        object: pull_request,
        formats: :html,
      ),
      form_actions: render_to_string(
        partial: "pull_requests/form_actions",
        object: pull_request,
        formats: :html,
        locals: {
          pull: pull_request,
          issue_node: pull_node,
        },
      ),
    })

  rescue ActiveRecord::RecordInvalid => err
    render_update_content_json({
      merging: render_to_string(
        partial: "pull_requests/merging",
        object: @pull_request,
        formats: :html,
        locals: {
          merging_error: {
            form_target: "js-queue-branch-form",
            title: "Merge attempt failed",
            message: err.record.errors.full_messages.to_sentence,
          },
        },
      ),
    }, status: :unprocessable_entity)
  end

  def update
    if params[:solo]
      entry.force_solo!
      flash[:notice] = "Forcing solo merge for PR ##{entry.pull_request.number} \"#{entry.pull_request.title}\"".truncate(100)
    elsif params[:jump]
      entry.jump!(actor: current_user)
      flash[:notice] = "Jumping the queue with PR ##{entry.pull_request.number} \"#{entry.pull_request.title}\"".truncate(100)
    else
      flash[:error] = "An unknown error occurred attempting to update the queue entry."
    end

    redirect_to :back
  end

  private

  def entry_adminable_by_current_user_required
    render_404 unless entry.adminable_by?(current_user)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def entry
    merge_queue.entries.includes(pull_request: [:issue]).find(params[:id])
  end

  def pull_request_required
    render_404 unless pull_request.present?
  end

  def content_authorization_required
    authorize_content(:pull_request, repo: current_repository)
  end

  def pull_request # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @pull_request if defined?(@pull_request)

    @pull_request = current_repository
      .issues
      .find_by_number(params[:pull_number].to_i)
      &.pull_request
  end
end
