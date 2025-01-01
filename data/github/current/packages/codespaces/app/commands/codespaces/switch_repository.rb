# typed: true
# frozen_string_literal: true

module Codespaces
  # Associates an existing codespace with a specified repository.
  # Does not change configuration of git remotes within the codespace.
  class SwitchRepository < Command
    attr_reader :codespace, :repository

    def initialize(codespace, repository)
      @codespace = codespace
      @repository = repository
    end

    def perform
      codespace.update!(repository: repository)

      Codespaces::BillingEntry.create!(
        codespace: codespace,
        billable_owner: codespace.billable_owner,
        codespace_owner: codespace.owner,
        codespace_guid: codespace.guid,
        codespace_plan_name: codespace.plan.name,
        repository: repository,
        copilot_workspace_id: codespace.copilot_workspace_id,
      )
    end
  end
end
