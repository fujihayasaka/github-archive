# frozen_string_literal: true

module ChatopRepoPause
  extend ActiveSupport::Concern

  PAUSE_CHATOPS_EVENT = "chatops"

  included do
    chatop :repo_pause,
           /repo[-_\s]pause\s+(?<github_nwo>.+)/,
           "repo pause NWO [--tenant TENANT] " \
           "- Immediately sets a repository into the 'paused due to inactivity' state" do
      github_nwo = jsonrpc_params[:github_nwo]
      tenant = jsonrpc_params[:tenant]
      repo = find_by_nwo!(github_nwo, tenant)
      repo.pause!(event_source: PAUSE_CHATOPS_EVENT)

      jsonrpc_success "Successfully paused `#{github_nwo}`"
    end

    chatop :repo_unpause,
           /repo[-_\s]unpause\s+(?<github_nwo>.+)/,
           "repo unpause NWO [--tenant TENANT] " \
           "- Immediately removes a repository from the 'pause dued to inactivity' state." do
      github_nwo = jsonrpc_params[:github_nwo]
      tenant = jsonrpc_params[:tenant]
      repo = find_by_nwo!(github_nwo, tenant)
      Activity::PauseManager.new(repo: repo).mark_as_active!(PAUSE_CHATOPS_EVENT)

      jsonrpc_success "Successfully unpaused `#{github_nwo}`"
    end
  end
end
