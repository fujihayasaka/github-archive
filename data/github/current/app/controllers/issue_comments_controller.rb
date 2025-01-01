# typed: true
# frozen_string_literal: true

class IssueCommentsController < AbstractRepositoryController
  include ShowPartial
  include TimelineHelper
  include CommentsHelper
  include IssuesHelper
  include Issues::RateLimitsDependency
  include Issues::RepositoryClusterDependency

  around_action :with_replica_repository_cluster, only: [:create]
  before_action :login_required
  before_action :require_issue_comment, only: [:update, :destroy, :edit_form]
  before_action :require_logged_in_and_not_blocked, only: [:create, :update]
  before_action :writable_repository_required, except: [:destroy, :edit_form, :comment_actions_menu]
  before_action :non_migrating_repository_required, only: [:destroy]
  before_action :content_authorization_required, only: [:create, :update]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:comment_actions_menu]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:edit_form]

  RATE_LIMITS_FEATURES = [
    :issues_service_mutative_actions_rate_limits, # are rate limits for issues-owned controller/actions enabled
    :issues_service_mutative_actions_rate_limits_new_max, # what are the new max rate limits for issues-owned controller/actions
    :issues_rate_limit_circuit_breaker, # whether to enable the circuit breaker for spammy users creating issues via issues#create
  ]

  preload_features RATE_LIMITS_FEATURES

  rate_limit_requests \
    max: :issues_service_rate_limits_max,
    ttl: 1.hour,
    key: :default_rate_limit_key,
    at_limit: :issues_service_rate_limits_at_limit,
    if: :issues_service_rate_limits_enabled?

  def create
    if issue = current_issue
      GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

      valid = true

      if blocked_from_commenting?(issue)
        if request.xhr?
          head :unprocessable_entity
        else
          redirect_to :back
        end
      end

      comment_body = params[:comment][:body]

      telemetry_tags = ["with_comment:#{comment_body.present?}"]
      telemetry_tags << "state_reason:#{params[:state_reason] || "completed"}"

      if !comment_body.nil? && !can_skip_creating_comment?
        @comment = issue.create_comment(current_user, comment_body)
        valid &&= @comment.persisted?
      elsif params[:comment_and_close] == "1"
        @comment = issue.comment_and_close(current_user, comment_body, params[:state_reason])
        valid &= @comment if comment_body.present?

        GitHub.dogstats.increment("issue.closed", tags: telemetry_tags)
      elsif params[:comment_and_open] == "1"
        if params[:state_reason] == "completed" || params[:state_reason] == "not_planned"
          @comment = issue.comment_and_close(current_user, comment_body, params[:state_reason] == "completed" ? nil : "not_planned")

          # This is on the re-open code flow as we're now about to change the close state on the reopen button.
          GitHub.dogstats.increment("issue.close_state_changed", tags: telemetry_tags)
        else
          @comment = issue.comment_and_open(current_user, comment_body)
        end
        valid &= @comment if comment_body.present?
      end

      async_mark_thread_as_read issue

      if valid && comment_body.present?
        GitHub.instrument "comment.create", user: current_user
        instrument_saved_reply_use(params[:saved_reply_id], "issue_comment")
      end

      respond_to do |format|
        format.html do
          if valid
            anchor = (@comment && @comment.valid?) ? "#issuecomment-#{@comment.id}" : ""
            redirect_to issue_path(issue.repository.owner, issue.repository, issue) + anchor
          else
            if @comment
              flash[:error] = @comment.errors.full_messages.to_sentence
            end

            redirect_to :back
          end
        end

        format.json do
          if valid
            if params[:context] == "project_sidebar"
              render_update_content_json({
                state_button_wrapper: render_to_string(
                  partial: "issues/state_button_wrapper",
                  object: issue,
                  formats: :html,
                  locals: {
                    issue: current_issue,
                  },
                ),
              })
            else
              discussion_categories = if current_repository.discussions_active?
                current_repository.available_discussion_categories
              else
                []
              end

              issue_node = Issue::ShowLoader.issue_node(
                issue,
                current_repository,
                current_user,
                pagination_params: { per_page: params[:timeline_per_page], timeline_since: helpers.discussion_last_modified_at&.iso8601(9) },
                cap_filter: cap_filter)

              partials = {
                timeline: render_to_string(
                  partial: "issues/timeline",
                  object: issue,
                  formats: :html,
                  locals: { issue: issue_node }
                )
              }

              # Render the remaining partials only if we are opening or closing an issue with a comment.
              if params[:comment_and_close] == "1" || params[:comment_and_open] == "1"
                partials.merge!({
                  sidebar: render_to_string(
                    partial: "issues/sidebar",
                    object: issue,
                    formats: :html,
                    locals: {
                      issue_node: issue_node,
                      discussion_categories: discussion_categories,
                    }
                  ),
                  form_actions: render_to_string(
                    partial: "issues/form_actions",
                    object: issue,
                    formats: :html,
                    locals: {
                      issue: current_issue,
                      issue_node: issue_node,
                    }
                  ),
                  issue_tab_count: render_to_string(
                    partial: "navigation/repository/tab_counter",
                    formats: :html,
                    locals: {
                      count: current_repository.open_issue_count_for(current_user),
                      label: "Issues"
                    }
                  ),
                })
              end

              render_update_content_json(partials)
            end
          else
            if @comment
              errors = @comment.errors.map { |error| error.message }
            else
              errors = ["Sorry, but we couldn't do that"]
            end
            render json: { errors: errors }, status: :unprocessable_entity
          end
        end
      end
    else
      render_404
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html do
        flash[:error] = e.record.errors.full_messages.to_sentence
        redirect_to issue_path(current_issue)
      end
      format.json do
        errors = e.record.errors.map { |error| error.message }
        return render json: { errors: errors.to_sentence }, status: :unprocessable_entity
      end
    end
  end

  def edit_form # rubocop:todo GitHub/UseRestfulActions
    comment = current_comment

    if can_modify_issue_comment?(comment) && !blocked_from_commenting?(current_issue)
      render Comments::EditForm::EditFormComponent.new(
        comment: comment,
        comment_context: params[:comment_context],
        textarea_id: params[:textarea_id],
        current_repository: current_repository,
        slash_commands_enabled: current_user.slash_commands_enabled?,
        slash_commands_surface: current_issue.pull_request? ? SlashCommands::PULL_REQUEST_COMMENT_SURFACE : SlashCommands::ISSUE_COMMENT_SURFACE,
      ), layout: false, formats: [:html]
    else
      head :forbidden
    end
  end

  def update
    comment = current_comment
    comment_params = issue_comment_params

    if can_modify_issue_comment?(comment) && comment_params.present?
      # prevent updates from stale data
      return render_stale_error(model: comment, error: "Could not edit comment. Please try again", path: issue_path(comment.issue)) if stale_model?(comment)

      async_mark_thread_as_read comment.issue

      if operation = TaskListOperation.from(params[:task_list_operation])
        text = operation.call(comment.body)
        Issues::Comments.update_comment(comment, text, current_user) if text
      else
        if Issues::Comments.update_comment(comment, comment_params[:body], current_user)
          duplicate_issue_events = comment.issue.
            build_duplicate_issue_events(comment.user, comment.duplicate_issues)
          duplicate_issue_events.each(&:save)
        end
      end
    end

    respond_to do |wants|
      wants.html do
        redirect_to issue_path(comment.issue)
      end

      wants.json do
        if comment.valid?
          render json: {
            "source" => comment.body,
            "body" => comment.body_html(context: { viewer: current_user, cap_filter: cap_filter, unfurl_references: true }),
            "newBodyVersion" => comment.body_version,
            "editUrl" => show_comment_edit_history_path(comment.global_relay_id),
          }
        else
          render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    if site_admin? || can_modify_issue_comment?(current_comment)
      current_comment.destroy
    elsif current_repository.archived?
      return respond_to do |format|
        format.json do
          render json: { error: "repository archived" },
                 status: :forbidden
        end
        format.all do
          render "repositories/states/archived",
                 status: :forbidden
        end
      end
    elsif current_comment&.issue.locked?
      return respond_to do |format|
        # This should be an edge case, likely only happening if the issue is
        # locked and someone without permissions tries to delete a comment
        # without reloading the page
        format.json do
          render json: { error: "issue locked" },
                 status: :forbidden
        end
      end
    end

    if request.xhr?
      head :ok
    else
      redirect_to issue_path(current_comment.issue)
    end
  end

  def comment_actions_menu # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?
    return render_404 unless current_comment&.issue

    current_comment.preload_viewer_attributes(current_user, current_repository)

    render partial: "comments/comment_header_details_menu", locals: {
      comment: current_comment,
      viewer: current_user,
      repository: current_repository,
      form_path: issue_comment_path(
        current_comment.repository.owner.display_login,
        current_comment.repository.name,
        current_comment.id
      ),
      issue_path: issue_path(
        current_repository.owner,
        current_repository,
        current_comment.issue),
      href: params[:href]
    }
  end

  # This overrides the service catalog tagging defined in `service_mapping` to modify the catalog service tagging to properly associate to pull requests.
  def logical_service # rubocop:todo GitHub/UseRestfulActions
    if current_comment && current_issue.pull_request?
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/#{PULL_REQUESTS_TAG}"
    else
      super
    end
  end

  private

  def ask_the_gatekeeper
    with_replica_repository_cluster { super }
  end

  def network_privilege_check
    with_replica_repository_cluster { super }
  end

  def perform_conditional_access_checks
    with_replica_repository_cluster { super }
  end

  def current_repository
    with_replica_repository_cluster { super }
  end

  def create_comment_body_is_a_hash?
    params.to_unsafe_h.with_indifferent_access.dig(:comment, :body).is_a?(Hash)
  end

  def issue_comment_params
    params.to_unsafe_h.with_indifferent_access[:issue_comment].slice :body
  end

  def can_skip_creating_comment?
    params[:comment_and_close].present? ||
      params[:comment_and_open].present?
  end

  memoize def current_comment
    comment = current_repository ? IssueComments::Public.by_id(params[:id].to_i, repository_id: current_repository.id) : nil
    return comment if comment && comment.readable_by?(current_user)
    nil
  end

  def require_issue_comment
    if current_comment.nil?
      render_404
    end
  end

  def require_logged_in_and_not_blocked
    if blocked_from_commenting?(current_issue)
      flash[:error] = "You can't perform that action at this time."
      redirect_to current_repository.permalink
    end
  end

  memoize def current_issue
    if action_name == "create"
      current_repository.issues.find_by_number(params[:issue].to_i)
    else
      current_comment.issue
    end
  end
  alias :timeline_owner :current_issue

  def content_authorization_required
    authorize_content(:issue_comment, issue: current_issue)
  end

  def route_supports_advisory_workspaces?
    case action_name
    when "comment_actions_menu", "destroy", "edit_form", "update"
      true
    else
      false
    end
  end
end
