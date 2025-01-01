# typed: true
# frozen_string_literal: true

class AutoMergeRequestsController < AbstractRepositoryController

  before_action :login_required
  before_action :load_current_pull_request

  include ShowPartial, TimelineHelper

  def create
    return render_404 unless current_user_can_push?

    author_email = params[:author_email].presence || current_user.git_author_email
    if current_user.is_enterprise_managed?
      return render_404 unless current_user.profile_email == author_email
      email = current_user.emails.find_by(email: current_user.email)
    else
      return render_404 unless email = current_user.emails.find_by(email: author_email)
    end

    AutoMergeRequest.enqueue!(
      pull_request: @pull,
      merge_method: params[:do],
      user: current_user,
      email: email,
      commit_title: params[:commit_title],
      commit_message: params[:commit_message],
      remote_ip: request.remote_ip,
    )

    respond_to do |format|
      # The `format.json` block must stay at the top here if any format
      # block is added in future, so that when the `Accept` header is `*/*`
      # we will continue to send JSON by default.
      format.json do
        pull_node = PullRequest::ShowLoader.issue_node(@pull, current_repository, current_user, cap_filter: cap_filter, pagination_params: { per_page: params[:timeline_per_page], timeline_since: helpers.discussion_last_modified_at&.iso8601 })
        render_update_content_json({
            sidebar: render_to_string(
              partial: "pull_requests/sidebar",
              object: @pull,
              formats: :html,
              locals: {
                pull_node: pull_node,
                pull: @pull,
              },
            ),
            merging: render_to_string(
              partial: "pull_requests/merging",
              object: @pull,
              formats: :html,
            ),
            form_actions: render_to_string(
              partial: "pull_requests/form_actions",
              object: @pull,
              formats: :html,
              locals: {
                pull: @pull,
                issue_node: pull_node,
              },
            ),
          })
      end
    end

  rescue AutoMergeRequest::Invalid => e
    merging_error = {
      form_target: "js-auto-merge-form" ,
      title: "Enabling auto-merge failed",
      unretryable: true,
      message: e.message,
    }
    render_update_content_json({
      merging: render_to_string(
        partial: "pull_requests/merging",
        object: @pull,
        formats: :html,
        locals: {
          merging_error:,
        },
      ),
    }, status: :unprocessable_entity)
  end

  def destroy
    return render_404 unless @pull.can_disable_auto_merge?(actor: current_user)

    @pull.auto_merge_request.disable(:manually_disabled, actor: current_user)
    @pull.reload

    respond_to do |format|
      # The `format.json` block must stay at the top here if any format
      # block is added in future, so that when the `Accept` header is `*/*`
      # we will continue to send JSON by default.
      format.json do
        pull_node = PullRequest::ShowLoader.issue_node(@pull, current_repository, current_user, cap_filter: cap_filter, pagination_params: { per_page: params[:timeline_per_page], timeline_since: helpers.discussion_last_modified_at&.iso8601 })
        render_update_content_json({
          sidebar: render_to_string(
            partial: "pull_requests/sidebar",
            object: @pull,
            formats: :html,
            locals: {
              pull_node: pull_node,
              pull: @pull,
            },
          ),
          merging: render_to_string(
            partial: "pull_requests/merging",
            object: @pull,
            formats: :html,
          ),
          form_actions: render_to_string(
            partial: "pull_requests/form_actions",
            object: @pull,
            formats: :html,
            locals: {
              pull: @pull,
              issue_node: pull_node,
            },
          ),
        })
      end
    end
  end

  private

  def load_current_pull_request
    @pull = current_repository.issues.find_by_number(params[:pull_id].to_i).try(:pull_request)
    return render_404 unless @pull
  end
end
