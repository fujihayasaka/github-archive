# typed: true
# frozen_string_literal: true

class IssuesTriageAgentController < AbstractRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = %w[
    IssuesTriageAgentController#update
    IssuesTriageAgentController#debug_submit
    IssuesTriageAgentController#config_save
  ].freeze

  before_action :login_required
  before_action :writable_repository_required
  before_action :ensure_triage_agent_enrolled
  before_action :ensure_push_access, except: [:show]
  before_action :parse_json_params, only: [:update, :debug_submit, :config_save]
  before_action :require_debug_mode, only: [:debug_prompts, :debug_submit]
  before_action :ensure_issue, only: [:debug_prompts, :debug_submit]
  before_action :ensure_manage_permission, only: [:config_save]

  allow_verified_fetch only: [:show, :update, :debug_prompts, :debug_submit, :config_show, :config_save]

  def show
    render json: {
      enabled: current_repository.issue_triage_enabled?,
      default_branch: current_repository.default_branch,
      config_exists: config_file_exists?,
      config_path: TriageAgent::Configuration::CONFIG_FILE_PATH,
      viewer_can_configure: Issues.domain.triage.can_manage_triage_agent?(current_user, current_repository)
    }
  end

  def update
    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])

    if enabled
      # When new config is enabled, reject enabling without a config file
      if IssuesTriageAgentFeature.new_config_enabled?(current_repository) && !config_file_exists?
        render json: { error: "config_required", message: "A configuration file is required." }, status: :unprocessable_entity
        return
      end

      current_repository.enable_issue_triage(actor: current_user)
    else
      current_repository.disable_issue_triage(actor: current_user)
    end

    render json: { enabled: current_repository.issue_triage_enabled? }
  end

  def config_show # rubocop:disable GitHub/UseRestfulActions
    commit_oid = current_repository.ref_to_sha(current_repository.default_branch)
    blob = commit_oid.present? ? current_repository.blob(commit_oid, TriageAgent::Configuration::CONFIG_FILE_PATH) : nil
    commitability = BranchRuleEvaluator.branch_commitability_status(
      current_repository, current_user, current_repository.default_branch
    )

    render json: {
      exists: blob.present?,
      content: blob.present? ? blob.data : TriageAgent::Configuration.basic_configuration_template(repository: current_repository),
      blob_oid: blob&.oid,
      config_path: TriageAgent::Configuration::CONFIG_FILE_PATH,
      default_branch: current_repository.default_branch,
      commit_info: {
        can_commit_status: commitability.to_s,
        author_emails: current_user.author_emails.map { |e| current_user.remove_shortcode(e) },
        default_email: current_user.default_author_email(current_repository),
        default_new_branch_name: current_repository.heads.temp_name(topic: "patch", prefix: current_user.display_login),
        commit_oid: current_repository.ref_to_sha(current_repository.default_branch),
        dco_signoff_enabled: current_repository.dco_signoff_enabled?,
      }
    }
  end

  def config_save # rubocop:disable GitHub/UseRestfulActions
    content = params[:content].to_s
    if content.blank?
      render json: { error: "Content is required" }, status: :unprocessable_entity
      return
    end

    commit_title = params[:message].presence || "Configure triage agent"
    commit_body = params[:description].to_s
    commit_message = [commit_title, commit_body].reject(&:blank?).join("\n\n")

    is_direct = params[:commit_choice] != "quick-pull"
    target_branch = is_direct ? current_repository.default_branch : params[:target_branch].to_s

    if target_branch.blank?
      render json: { error: "Branch name is required" }, status: :unprocessable_entity
      return
    end

    result = commit_triage_agent_config(
      content: content,
      branch: target_branch,
      commit_message: commit_message,
      commit_title: commit_title,
      commit_body: commit_body,
      is_creating_pr: !is_direct
    )

    if result[:ok]
      # Auto-enable triage agent on first config creation
      unless current_repository.issue_triage_enabled?
        current_repository.enable_issue_triage(actor: current_user)
      end

      render json: {
        ok: true,
        redirect_url: result[:redirect_url],
        pull_request_url: result[:pull_request_url],
      }
    else
      render json: { error: result[:error] }, status: result[:status] || :unprocessable_entity
    end
  rescue StandardError => e
    Failbot.report(e, context: {
      action: "config_save",
      repository_id: current_repository.id,
    })
    render json: { error: "An internal error occurred. Please try again." }, status: :internal_server_error
  end

  def debug_prompts # rubocop:disable GitHub/UseRestfulActions
    twirp_problem_statement = TriageAgent::PromptBuilder.generate_issue_triage_problem_statement(issue: @issue)
    twirp_triage_prompt = TriageAgent::PromptBuilder.generate_triage_agent_prompt(repository: current_repository)

    render json: {
      issue_number: @issue.number,
      twirp: {
        developer_prompt: twirp_triage_prompt,
        user_prompt: twirp_problem_statement,
      },
    }
  end

  def debug_submit # rubocop:disable GitHub/UseRestfulActions
    developer_prompt = params[:developer_prompt].to_s.strip
    user_prompt = params[:user_prompt].to_s.strip

    if developer_prompt.blank? || user_prompt.blank?
      render json: { error: "developer_prompt and user_prompt are required and must be non-blank." }, status: :unprocessable_entity
      return
    end

    Issues.domain.triage.trigger_triage_agent_job_twirp(
      issue: @issue,
      repository: current_repository,
      problem_statement: user_prompt,
      triage_prompt: developer_prompt
    )

    render json: { status: "submitted" }
  rescue StandardError => e
    Failbot.report(e, context: {
      action: "debug_submit",
      repository_id: current_repository.id,
      issue_number: params[:issue_number],
    })
    render json: { error: "An internal error occurred. Please try again." }, status: :internal_server_error
  end

  private

  def config_file_exists?
    Issues.domain.triage.config_file_exists?(current_repository)
  end

  def ensure_triage_agent_enrolled
    unless IssuesTriageAgentFeature.enrolled?(current_repository)
      render_404
    end
  end

  def ensure_push_access
    render_404 unless current_user_can_push?
  end

  def require_debug_mode
    unless employee? && FeatureFlag.vexi.enabled?(:issues_triage_agent_debug, current_user, current_repository, default: false)
      render_404
    end
  end

  def ensure_issue
    issue_number = params[:issue_number].to_i
    @issue = current_repository.issues.find_by(number: issue_number)

    unless @issue
      render json: { error: "Issue not found" }, status: :not_found
    end
  end

  def ensure_manage_permission
    unless Issues.domain.triage.can_manage_triage_agent?(current_user, current_repository)
      render json: { error: "You do not have permission to manage the triage agent" }, status: :forbidden
    end
  end

  def commit_triage_agent_config(content:, branch:, commit_message:, commit_title:, commit_body:, is_creating_pr:)
    branch = Git::Ref.normalize(branch)

    if branch.nil?
      if is_creating_pr
        branch = current_repository.heads.temp_name(topic: "triage-agent-config")
      else
        return { ok: false, error: "Invalid branch name", status: :unprocessable_entity }
      end
    end

    commit_oid = current_repository.ref_to_sha(current_repository.default_branch)
    normalized_content = content.gsub(/\r\n/, "\n")
    files = { TriageAgent::Configuration::CONFIG_FILE_PATH => normalized_content }

    # For PR flow, ensure the branch name doesn't collide with an existing one
    if is_creating_pr && current_repository.heads.exist?(branch)
      branch = current_repository.heads.temp_name(topic: branch)
    end

    commit_result = current_repository.commit_change_for_user(
      author: current_user,
      author_email: params[:author_email],
      branch: branch,
      files: files,
      message: commit_message,
      before_oid: commit_oid,
      reflog_data: request_reflog_data("triage agent config"),
      sign: true
    )

    if commit_result.nil?
      return {
        ok: false,
        error: "Unable to create commit",
        status: :unprocessable_entity,
      }
    end
    commit_sha, branch_name, err_msg = commit_result

    if err_msg
      return { ok: false, error: err_msg, status: :unprocessable_entity }
    end

    unless commit_sha
      return { ok: false, error: "No changes to commit", status: :unprocessable_entity }
    end

    pull_request = nil
    if is_creating_pr
      pull_request = PullRequest.create_for(current_repository, {
        base: current_repository.default_branch,
        head: branch_name,
        title: commit_title,
        body: commit_body,
        user: current_user,
      })

      unless pull_request.valid?
        return { ok: false, error: "Pull request could not be created", status: :unprocessable_entity }
      end
    end

    repo_url = "/#{current_repository.owner_display_login}/#{current_repository.name}"
    pr_url = pull_request ? "#{repo_url}/pull/#{pull_request.number}" : nil

    {
      ok: true,
      redirect_url: pr_url || repo_url,
      pull_request_url: pr_url,
    }
  end

end
