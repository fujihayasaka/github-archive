# frozen_string_literal: true

require "thor"

require "stafftools/cli/repo"
require "stafftools/cli/version_updates"

require "stafftools/cli/util"

module Stafftools
  module Cli
    class Main < Thor
      def self.exit_on_failure?
        true
      end

      desc "check-github-app [--warn]", "Check we can connect to the GitHub API using the current config values."
      option :warn, type: :boolean
      def check_github_app
        check = CheckGitHubApp.new
        app = check.run

        if app
          say "🎉 GitHub is accessible via #{app[:html_url]}", :green
        else
          say "🛑 Cannot connect to GitHub due to the following issues: \n\n", :red

          check.problems.each do |problem|
            say problem, :red
          end

          say Util.github_app_help if Rails.env.development?

          exit 1 unless options[:warn]
        end
      end

      desc "repo SUBCOMMAND", "Manage Dependabot for individual repositories"
      subcommand :repo, Repo

      desc "version-updates SUBCOMMAND", "Trigger verion update jobs"
      subcommand :version_updates, VersionUpdates

      desc "debug-credentials NWO PACKAGE_MANAGER PUBLIC_KEY",
           "Print credentials for repo & package manager, encrypted with base64 public-key"
      option :directory,
             alias: :d,
             default: "/",
             desc: "Repo directory to find configuration"
      def debug_credentials(nwo, package_manager, public_key)
        _, repo = Util.find(nwo)
        Util.validate_package_manager(package_manager)

        unless repo.account.github_login == "dsp-testing"
          say "🛑 This command is only available for repos in the dsp-testing org for now", :red
          exit 1
        end

        # We persist '/' as '/.', so correct any inputs accordingly
        #
        # See: UpdateConfig::clean_directory
        directory = directory_from(options)

        update_config = repo.update_configs.active.find_by(
          package_manager: package_manager,
          directory: directory
        )
        unless update_config
          say "#{nwo} does not have any active update configs for #{package_manager} and directory #{directory}.", :red
          exit 1
        end

        creds = EncryptRegistryCredentialsForDebugging.new(update_config, public_key).run

        say <<~HELP, :green
          Your credentials for #{nwo} are:

          Encrypted credentials:
          #{creds.encrypted_credential_blob}
        HELP
      end

      private

      def directory_from(options)
        return "/." if options[:directory] == "/"

        options[:directory]
      end
    end
  end
end
