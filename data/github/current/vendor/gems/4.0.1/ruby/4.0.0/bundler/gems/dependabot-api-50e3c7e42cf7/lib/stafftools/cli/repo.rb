# frozen_string_literal: true

require "thor"

module Stafftools
  module Cli
    class Repo < Thor
      desc "setup NWO", "Perform initial setup on a Repository that has the development app installed."
      def setup(nwo)
        _, repo_name = Util.parse_nwo(nwo)

        installation = fetch_installation_for_repository(nwo)

        account = FindOrCreateAccount.new(github_account: installation[:account]).run
        ActivateAccount.new(account: account, installation_id: installation[:id], sender: installation[:account]).run

        repository_details = fetch_repo(account, repo_name)
        FindOrCreateRepo.new(github_repo: repository_details).run

        say "Account and Repo set up, attempting to sync config file.", :green
        invoke :sync, [nwo]
      end

      desc "sync NWO", "Refresh the configuration from a Repository already set up locally."
      def sync(nwo)
        account, repo = Util.find(nwo)
        ProcessConfigFile.new(account: account, repo_name: repo.name, repo_github_id: repo.github_id, quiet: true).run

        active_config_count = repo.update_configs.active.count
        say "Successfully checked config files for #{nwo}. Activated #{active_config_count} configs.", :green
      end

      private

      def fetch_installation_for_repository(nwo)
        github_app_client.find_repository_installation(nwo)
      rescue Octokit::NotFound
        say "The '#{Prius.get(:github_integration_name)}' integration is not installed on #{nwo}.", :red
        exit 1
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
        say "GITHUB_INTEGRATION_PRIVATE_KEY does not appear to be a valid private key.", :red
        say Util.github_app_help if Rails.env.development?
        exit 1
      end
    end
  end
end
