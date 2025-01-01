# typed: true
# frozen_string_literal: true

class Api::RequiredWorkflows < Api::App
  include ReceiveSchemaWithOpenApi

  get "/organizations/:organization_id/actions/required_workflows/:required_workflow_id", operation_id: "actions/get-required-workflow" do
    current_org = find_org!

    control_access :read_required_workflows,
      resource: current_org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_deprecation_notice
  end

  get "/organizations/:organization_id/actions/required_workflows", operation_id: "actions/list-required-workflows" do
    current_org = find_org!

    control_access :read_required_workflows,
      resource: current_org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_deprecation_notice
  end

  post "/organizations/:organization_id/actions/required_workflows", operation_id: "actions/create-required-workflow" do
    current_org = find_org!

    control_access :write_required_workflows,
      resource: current_org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_deprecation_notice
  end

  patch "/organizations/:organization_id/actions/required_workflows/:required_workflow_id", operation_id: "actions/update-required-workflow" do
    current_org = find_org!

    control_access :write_required_workflows,
      resource: current_org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_deprecation_notice
  end

  delete "/organizations/:organization_id/actions/required_workflows/:required_workflow_id", operation_id: "actions/delete-required-workflow" do
    current_org = find_org!

    control_access :write_required_workflows,
      resource: current_org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_deprecation_notice
  end

  get "/organizations/:organization_id/actions/required_workflows/:required_workflow_id/repositories", operation_id: "actions/list-selected-repositories-required-workflow" do
    current_org = find_org!

    control_access :read_required_workflows,
      resource: current_org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_deprecation_notice
  end

  delete "/organizations/:organization_id/actions/required_workflows/:required_workflow_id/repositories/:repository_id", operation_id: "actions/remove-selected-repo-from-required-workflow" do
    current_org = find_org!

    control_access :write_required_workflows,
      resource: current_org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_deprecation_notice
  end

  put "/organizations/:organization_id/actions/required_workflows/:required_workflow_id/repositories/:repository_id", operation_id: "actions/add-selected-repo-to-required-workflow" do
    current_org = find_org!

    control_access :write_required_workflows,
      resource: current_org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    handle_deprecation_notice
  end

  put "/organizations/:organization_id/actions/required_workflows/:required_workflow_id/repositories", operation_id: "actions/set-selected-repos-to-required-workflow" do
    current_org = find_org!

    control_access :write_required_workflows,
      resource: current_org,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true


    handle_deprecation_notice
  end

  # Get all the required workflows that have run at least once for a repository
  get "/repositories/:repository_id/actions/required_workflows", operation_id: "actions/list-repo-required-workflows" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_deprecation_notice
  end

  # Get a single required workflow run entity that has run at least once for a repository
  get "/repositories/:repository_id/actions/required_workflows/:required_workflow_id", operation_id: "actions/get-repo-required-workflow" do
    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_deprecation_notice
  end

  # Get the billable information for a required workflow run entity
  get "/repositories/:repository_id/actions/required_workflows/:required_workflow_id/timing", operation_id: "actions/get-repo-required-workflow-usage" do
    deliver_error!(404) if GitHub.enterprise?

    repo = find_repo!

    control_access :read_actions,
      resource: repo,
      user: current_user,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_deprecation_notice
  end

  private

  def handle_deprecation_notice
    blog_url = "#{GitHub.blog_url}/2023-10-11-enforcing-code-reliability-by-requiring-workflows-with-github-repository-rules/"
    deprecation_date = GitHub.enterprise? ? "GHES 3.12" : "January 2024"
    deliver_error! 422, message: "As of #{deprecation_date}, this feature is fully deprecated and creating required workflows is only available with repository rulesets. All existing workflows have been automatically migrated to rulesets. Learn more about rulesets: #{blog_url}"
  end

end
