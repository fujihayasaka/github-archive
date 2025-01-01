# typed: true
# frozen_string_literal: true

class Issues::BranchController < IssuesController

  include Issues::RateLimitsDependency

  before_action :login_required
  before_action :issue_required
  before_action :writable_repo_required, only: [:new, :create]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    optional: false, only: [:new]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    optional: false, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new], optional: true

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
    error_message = nil
    branch_name = params[:name]
    source_branch = params[:branch]
    branch_issue_reference =
      begin
        BranchIssueReference.create_with_new_branch!(
          issue: current_issue,
          repository: repository,
          creator: current_user,
          new_branch_name: branch_name,
          # source_branch will be blank if the user doesn't
          # open the <ref-selector> dropdown. In that case they intend
          # to pick the default branch.
          source_branch_name: source_branch || repository.default_branch,
          reflog_data: request_reflog_data("web branch create from issue")
        )
      rescue ActiveRecord::RecordInvalid => e
        error_message = invalid_branch_error_message(e.record)
        Failbot.report(e)
        false
      rescue Git::Ref::ExistsError
        error_message = "Sorry, the branch #{branch_name} already exists."
        false
      rescue Git::Ref::HookFailed
        error_message = "Sorry, the branch #{branch_name} could not be created."
        false
      rescue Git::Ref::InvalidName, Git::Ref::UpdateFailed, Hydro::Protobuf::InvalidValueError
        error_message = "Sorry, that branch name is invalid."
        false
      rescue BranchIssueReference::SourceBranchNotFound => e
        error_message = e.message
        false
      rescue GitRPC::InvalidFullOid, Git::Ref::UpdateError
        error_message = "Sorry, there was an error creating the branch."
        false
      rescue StandardError
        error_message = "Sorry, the branch #{branch_name} could not be created."
        false
      end
    if branch_issue_reference
      tag = %w[checkout-locally github-desktop codespace].include?(params[:after_create]) ? params[:after_create] : nil

      GitHub.dogstats.increment("branch_for_issue.created", tags: ["source:web", "after_create:#{tag}"])

      if params[:after_create] == "checkout-locally"
        render Branch::LocalCheckoutComponent.new(branch_name: branch_name), layout: false
      elsif params[:after_create] == "github-desktop"
        render Branch::OpenInDesktopComponent.new(branch_name: branch_name, repository: branch_issue_reference.repository), layout: false
      else
        render Codespaces::IssueBranchComponent.new(repository: branch_issue_reference.repository, branch_name: branch_name), layout: false
      end
    else
      render Branch::CreateErrorComponent.new(message: error_message), layout: false, status: 422
    end
  end

  # renders the create branch button's details
  def new
    render "issues/branch/new", layout: false
  end

  private

  memoize def repository
    if params[:repo].present?
      Repositories::Public.find_active!(params[:repo])
    else
      current_issue.repository
    end
  end

  def writable_repo_required
    unless BranchIssueReference.creatable_for?(user: current_user, issue: current_issue, repository: repository)
      render_404
    end
  end

  def invalid_branch_error_message(record)
    errors = record.errors
    branch_name = record.branch_name

    if errors.of_kind?(:branch_name, :taken)
      "Sorry, the branch #{branch_name} already exists."
    elsif errors.of_kind?(:branch_name, :blank)
      "Sorry, the branch name cannot be blank."
    else
      "Sorry, the branch #{branch_name} could not be created."
    end
  end
end
