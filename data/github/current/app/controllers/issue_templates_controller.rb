# typed: true
# frozen_string_literal: true

class IssueTemplatesController < AbstractRepositoryController

  include Issues::RateLimitsDependency

  before_action :login_required
  before_action :ask_the_gatekeeper
  before_action :pushers_only

  javascript_bundle :community
  javascript_bundle :"structured-issues"

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Spokes,
    optional: false, only: [:edit]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit],
    optional: true

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

  def edit
    branch = params[:branch] || current_repository.default_branch
    # filter out structured templates, since the editor doesn't support them yet
    issue_templates = current_repository.issue_templates.templates.reject(&:structured?)

    respond_to do |format|
      format.html do
        render "issue_templates/edit", layout: "repository", locals: { branch: branch, issue_templates: issue_templates }
      end
    end
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    issue_template = IssueTemplate.preview(
      current_repository,
      params[:current],
      GitHub::JSON.load(params[:templates], failsafe: true),
    )

    render json: {
      html: render_to_string(partial: "issue_templates/template", formats: :html, locals: { template: issue_template }),
      markdown: issue_template.to_markdown,
      filename: issue_template.filename,
    }
  end

  def create_many # rubocop:todo GitHub/UseRestfulActions
    templates = if params.has_key?(:templates)
      params.require(:templates).map { |t| t.permit!.to_hash }
    else
      []
    end

    # ensure each keys which represents the filename is using binary encoding
    # since this will be given to gitrpc to create a commit
    templates.each do |template|
      template.transform_keys!(&:b)
    end

    issue_templates = IssueTemplates.new(current_repository)

    branch = params["commit-choice"] == "direct" ? current_repository.default_branch : params[:target_branch]

    commit_params = params.require(:commit)

    result = issue_templates.update(templates,
      updater: current_user,
      commit_title: commit_params[:title],
      commit_body: commit_params[:description],
      branch: branch,
      reflog_data: request_reflog_data("issue template builder"),
      remove_issue_forms: false
    )

    if result.ok?
      flash[:notice] = "Updated issue templates for this repository" unless result.pull_request
      redirect_to result.pull_request || current_repository
    else
      # Pre-receive hook notification messages include the output of the pre-receive hook.
      if result.hook_output
        flash[:hook_message] = result.error
        flash[:hook_out] = result.hook_output
      else
        flash[:error] = result.error
      end
      redirect_to edit_issue_templates_path(current_repository.owner, current_repository)
    end
  end

  def markdown_preview # rubocop:todo GitHub/UseRestfulActions
    render html: Issue.new(body: params[:markdown]).body_html
  end
end
