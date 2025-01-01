# typed: true
# frozen_string_literal: true

class CommentPreviewController < ApplicationController
  include OrganizationsHelper
  include TextHelper
  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  include Issues::RateLimitsDependency
  include Issues::RepositoryClusterDependency

  around_action :with_replica_repository_cluster, only: [:show]
  allow_verified_fetch only: [:show]

  FLAGS = [:adaptive_card_markdown_parsing].freeze
  preload_features FLAGS, only: [:show]

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

  # NOTE: <KLAXON>This behavior is shared between dotcom and gist.</KLAXON>
  #       If you change this, or it's route, please review the Gist routes as well
  #       as testing comment previewing in Gist on gist-garage or production.
  def show
    markdown = params[:text]
    context = default_html_filter_context.merge(current_user: current_user)

    html = track_time(metric: "markdown.dist.time", tags: ["action:preview"]) do
      context[:entity] = entity_for_context
      if entity_for_context&.adaptive_card_parsing_enabled?
        if subject = discussion || issue || pull_request
          context[:subject] = subject
        end
      elsif subject = saved_reply
        context[:subject] = subject
      end
      context[:gist] = gist_for_context
      context[:organization] = org_for_context
      context[:memex_project] = project_for_context
      context[:original_lines] = original_lines
      context[:path] = params[:path] if params[:path]
      context[:line_number] = params[:line_number].to_i if params[:line_number]
      context[:line_number] = params[:lineNumber].to_i if params[:lineNumber]
      context[:start_line_number] = params[:start_line_number].to_i if params[:start_line_number]
      context[:subject_type] = params[:subject_type] if params[:subject_type]
      # Control behavior in filters if the comment is being previewed
      context[:previewing] = true

      if params[:markdown_unsupported] && params[:markdown_unsupported] == "true"
        GitHub::Goomba::EmailPipeline.to_html(markdown, context).gsub("\n", "<br>\n").html_safe # rubocop:disable Rails/OutputSafety
      else
        context[:unfurl_references] = unfurl_enabled_for_type?
        context[:viewer] = current_user
        context[:cap_filter] = cap_filter
        GitHub::Goomba::MarkdownPipeline.to_html(markdown, context)
      end
    end
    render html: html
  end

  memoize def current_repository # rubocop:todo GitHub/UseRestfulActions
    with_replica_repository_cluster do
      if params[:repository].present?
        Repository.find_by(id: params[:repository])
      end
    end
  end

  private

  def tenant_verification_enforceable
    return :no if action_name == "show"
    :yes
  end

  def ip_allowlist_enforceable
    return :no if action_name == "show"
    super
  end

  def external_conditional_access_policy_enforceable
    return :no if action_name == "show"
    super
  end

  def require_active_external_identity_session?
    return false if action_name == "show"
    true
  end

  def two_factor_enforceable
    return :no if action_name == "show"
    :yes
  end

  # Returns the requested entity (repository) if the user can access it.
  memoize def entity_for_context
    repo = current_repository
    return unless logged_in? && repo && repo.pullable_by?(current_user)

    # Use CAP filter to ensure an unauthorized repository is not returned
    return if cap_filter.unauthorized_resources([repo]).any?

    repo
  end

  memoize def gist_for_context
    if params[:subject_type] == "Gist"
      if params[:subject]
        Gist.find_by(repo_name: params[:subject])
      else
        Gist.new
      end
    end
  end

  # Returns the requested organization if the user can access it.
  def org_for_context
    return unless org = current_organization

    # Use CAP filter to ensure an unauthorized org is not returned
    return if cap_filter.unauthorized_resources([org]).any?

    org
  end

  def project_for_context
    return unless params[:subject_type] == "Project" && params[:project]
    project = MemexProject.find_by(id: params[:project])

    return unless project&.readable_by?(current_user)

    return if cap_filter.unauthorized_resources([project.owner]).any?

    project
  end

  def unfurl_enabled_for_type?
    # Projects are not bound to a repository, but we still want to enable rich unfurling for issue/pr links
    return true if params[:subject_type] == "Project" || params[:project].present?

    !entity_for_context.nil? &&
      (params[:subject_type] == "Issue" || params[:subject_type] == "IssueComment" || params[:issue].present? ||
        params[:subject_type] == "PullRequest" || params[:pull_request].present? ||
        params[:subject_type] == "Discussion" || params[:discussion].present?)
  end

  memoize def discussion
    if entity_for_context && params[:subject_type] == "Discussion"
      entity_for_context.discussions.find_by_number(params[:subject])
    elsif entity_for_context && params[:discussion].present?
      entity_for_context.discussions.find_by(id: params[:discussion])
    end
  end

  memoize def issue
    if entity_for_context && params[:subject_type] == "Issue"
      entity_for_context.issues.find_by_number(params[:subject])
    elsif entity_for_context && params[:issue].present?
      entity_for_context.issues.find_by(id: params[:issue])
    end
  end

  memoize def pull_request
    if entity_for_context && params[:subject_type] == "PullRequest"
      entity_for_context.issues.find_by_number(params[:subject])&.pull_request
    elsif entity_for_context && params[:pull_request].present?
      entity_for_context.pull_requests.find_by(id: params[:pull_request])
    end
  end

  memoize def saved_reply
    SavedReply.find(params[:subject]) if params[:subject_type] == "SavedReply" && params[:subject].present?
  end

  def original_lines
    return params[:original_line] if params[:original_line]
    return params[:originalLine] if params[:originalLine]

    return unless params[:comment_id] || (params[:path] && params[:line_number] && commits_present?)

    if pull_request
      if params[:comment_id].present?
        comment = pull_request.review_comments.where(id: params[:comment_id]).first
        PullRequestReviewComment::SuggestedChangeSelection.from_persisted_comment(comment).lines
      else
        PullRequestReviewComment::SuggestedChangeSelection.new(
          pull: pull_request,
          path: params[:path],
          start_commit_oid: params[:start_commit_oid],
          end_commit_oid: params[:end_commit_oid],
          base_commit_oid: params[:base_commit_oid],
          start_line: params[:start_line_number]&.to_i,
          start_side: params[:start_side],
          line: params[:line_number]&.to_i,
          side: params[:side],
        ).lines
      end
    end
  end

  def commits_present?
    [params[:start_commit_oid], params[:end_commit_oid], params[:base_commit_oid]].all?(&:present?)
  end

  def initialize_hydro_context
    super

    if hydro_context && hydro_context[:enabled] && org_for_context
      hydro_context.merge!({
        current_org: org_for_context.name,
        current_org_id: org_for_context.id,
      })
    end
  end
end
