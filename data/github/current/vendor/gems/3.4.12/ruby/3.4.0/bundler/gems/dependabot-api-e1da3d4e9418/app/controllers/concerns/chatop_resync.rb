# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
module ChatopResync
  extend ActiveSupport::Concern

  included do
    chatop :resync, /resync\s+(?<nwo_list>[^,\s]+(?:[,\s]+[^,\s]+)*)/, <<~DESC do
      NAME
        resync NWO_LIST or resync OWNER -- Queue up a background job to resynchronize one or more repos or all repos on an account

      SYNOPSIS

        resync NWO_LIST [--force] [--tenant TENANT]

        --force    Reset the configuration of a *repo* before resyncing (does not apply to accounts)
        --tenant   The tenant to resync the repo for

      EXAMPLES

        Resync the configuration for `education/teachers_pet`

          resync education/teachers_pet

        Resync the configurations for `education/teachers_pet` and `education/student_tool`

          resync education/teachers_pet,education/student_tool

        Resync the configuration for `education`

          resync education

        Remove, then resync the config files for `education/teachers_pet` and `education/student_tool`

          resync education/teachers_pet,education/student_tool --force
    DESC

      # Split on comma or whitespace
      repos = jsonrpc_params[:nwo_list].split(/[,\s]+/).map(&:strip)
      tenant = jsonrpc_params[:tenant]
      success_messages = []

      repos.each do |nwo|
        if valid_nwo?(nwo)
          repo = find_by_nwo!(nwo, tenant)

          ResetConfigFileJob.perform_later(repo: repo) if jsonrpc_params["force"]

          # wait 5 seconds to give the reset job a chance to finish
          Stafftools::ResyncRepoJob.set(wait: 5.seconds).perform_later(account: repo.account, github_id: repo.github_id)

          success_messages << "Enqueued a resync job for the repository '#{nwo}'"
        else
          account = find_account!(nwo, tenant)
          Stafftools::ResyncAccountJob.perform_later(account: account)

          success_messages << "Enqueued a resync job for the account '#{account.github_login}'"
        end
      end

      jsonrpc_success success_messages.join("\n")
    end
  end
end
# rubocop:enable Metrics/BlockLength
