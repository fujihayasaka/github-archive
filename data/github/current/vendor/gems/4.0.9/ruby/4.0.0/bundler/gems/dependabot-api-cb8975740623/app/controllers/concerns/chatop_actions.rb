# frozen_string_literal: true

module ChatopActions
  extend ActiveSupport::Concern

  FIDO_PROTECTED_ACTIONS = %i(actions_set_branch actions_clear_branch).freeze

  included do
    before_action :require_fido_2fa, only: FIDO_PROTECTED_ACTIONS

    chatop :actions_set_branch,
           /actions\s+set[_-]branch\s+(?<nwo>\S*)\s+(?<branch_name>\S*)?/,
           "actions set-branch [--tenant TENANT] - Use the specified branch of the updater action" do
      nwo = jsonrpc_params[:nwo]
      branch_name = jsonrpc_params[:branch_name]
      tenant = jsonrpc_params[:tenant]

      repo = find_by_nwo!(nwo, tenant)
      RunUpdater::Actions::Workflow.set_branch_for(repo: repo, branch_name: branch_name)

      jsonrpc_success "#{nwo} will now use the #{branch_name} branch of #{RunUpdater::Actions::Workflow::ACTION_NWO}"
    end

    chatop :actions_clear_branch,
           /actions\s+clear[_-]branch\s+(?<nwo>\S*)?/,
           "actions clear-branch [--tenant TENANT] " \
           "- Reset the repository to the current stable release of the updater action" do
      nwo = jsonrpc_params[:nwo]
      tenant = jsonrpc_params[:tenant]

      repo = find_by_nwo!(nwo, tenant)
      RunUpdater::Actions::Workflow.clear_branch_for(repo: repo)

      jsonrpc_success "#{nwo} will now use the `#{RunUpdater::Actions::Workflow::LATEST_VERSION_TAG}` " \
                      "release of #{RunUpdater::Actions::Workflow::ACTION_NWO}"
    end
  end
end
