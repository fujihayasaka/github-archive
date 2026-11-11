# frozen_string_literal: true

require "thor"

module Stafftools
  module Cli
    module Util
      def self.shell
        @shell ||= Thor::Base.shell.new
      end

      def self.find(nwo)
        owner_login, repo_name = parse_nwo(nwo)
        account = Account.find_by(github_login: owner_login)

        unless account
          shell.say "Account '#{owner_login}' not found.", :red
          exit 1
        end

        repo = account.repos.find_by(name: repo_name)

        unless repo
          shell.say "Repo '#{nwo}' not found."
          exit 1
        end

        [account, repo]
      end

      def self.parse_nwo(nwo)
        github_login, repo_name = nwo.split("/")

        if repo_name.blank?
          shell.say "'#{nwo}' does not appear to be a valid Repository name", :red
          exit 1
        end

        [github_login, repo_name]
      end

      def self.validate_package_manager(package_manager)
        return if PackageManagers::ALL.include?(package_manager)

        shell.say "The package manager '#{package_manager}' is not supported.", :red
        shell.say "\nIt must be one of:\n  #{PackageManagers::ALL.join("\n  ")}"
        exit 1
      end

      def self.github_app_help
        <<~HELP

          🚧 Connecting to the dependabot-dev app in GitHub.com 🚧

          1 Please ensure you have setup your .env.local file using the example:
              cp .env.local.example .env.local

          2 Visit the app management page and generate a private key for your use:
              https://github.com/organizations/dsp-testing/settings/apps/dependabot-dev

          3 Add this key to GITHUB_INTEGRATION_PRIVATE_KEY in your .env.local file

          4 Re-check your connection
              script/dependabot check-github-app

          If you need to connect to GitHub running in another environment, see our documentation:
            https://github.com/github/dependabot-updates/tree/main/docs/development
        HELP
      end
    end
  end
end
