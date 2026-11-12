# frozen_string_literal: true

# This chatop is meant to fix repositories that have the Dependabot App installed,
# but Dependabot API has no record of the account. This can happen if an account setup webhook fails to send.
#
# rubocop:disable Metrics/BlockLength
module ChatopSetup
  extend ActiveSupport::Concern

  included do
    chatop :setup, /setup\s+(?<nwo_list>[^,\s]+(?:[,\s]+[^,\s]+)*)/, <<~DESC do
      NAME
        setup NWO_LIST -- Queue up a background job to setup one or more repos or all repos on an account

      SYNOPSIS

        setup NWO_LIST

      EXAMPLES

        Setup the configuration for `education/teachers_pet`

          setup education/teachers_pet

        Setup the configurations for `education/teachers_pet` and `education/student_tool`

          setup education/teachers_pet,education/student_tool

    DESC

      # Split on comma or whitespace
      repos = jsonrpc_params[:nwo_list].split(/[,\s]+/).map(&:strip)
      success_messages = []

      repos.each do |nwo|
        raise ChatopsController::CommandError, "`#{nwo}` is not a valid repository name." unless valid_nwo?(nwo)

        _, repo_name = nwo.split("/")
        # Find the Dependabot App installation on an Account
        installation = fetch_installation_for_repository(nwo)

        account = FindOrCreateAccount.new(github_account: installation[:account]).run
        ActivateAccount.new(account: account, installation_id: installation[:id], sender: installation[:account]).run

        next unless account.reload.active?

        # Search for the repository on the monolith
        repository_details = fetch_repo(account, repo_name)
        # Call FindOrCreateRepo to onboard the repo to Dependabot in case it is not already onboarded
        repo = FindOrCreateRepo.new(github_repo: repository_details).run

        process_config_file(repo)

        success_messages << "Enqueued a setup job for the repository `#{nwo}`."
      end

      jsonrpc_success success_messages.join("\n")
    end
  end

  private

  # Process the config file without triggering any UpdateJobs.
  def process_config_file(repo)
    ProcessConfigFile.new(
      account: repo.account,
      repo_name: repo.name,
      repo_github_id: repo.github_id,
      quiet: true
    ).run
  end

  def fetch_installation_for_repository(nwo)
    github_app_client.find_repository_installation(nwo)
  rescue Octokit::NotFound
    raise ChatopsController::CommandError, "Dependabot is not enabled for `#{nwo}`."
  end

  def fetch_repo(account, repo_name)
    installation_client(account).repo("#{account.github_login}/#{repo_name}")
  end

  def installation_client(account)
    @installation_client ||= GitHubHelpers::ClientWithRetries.new(account: account)
  end

  def github_app_client
    @github_app_client ||= GitHubHelpers::ClientWithRetries.new(bearer_token: GitHubHelpers.integration_token)
  rescue OpenSSL::PKey::RSAError
    raise CommandError, "Not connected to a production environment." if Rails.env.development?

    raise CommandError, "GITHUB_INTEGRATION_PRIVATE_KEY does not appear to be a valid private key."
  end
end
# rubocop:enable Metrics/BlockLength
