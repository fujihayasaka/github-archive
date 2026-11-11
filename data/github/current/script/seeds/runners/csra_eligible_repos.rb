# typed: true
# frozen_string_literal: true

require_relative "../runner"
require_relative "csra_base"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CsraEligibleRepos < Seeds::Runner
      def self.help
        <<~HELP
        Creates CSRA-eligible repositories for testing the repo picker.

        Sets up:
        - An organization (csra-test-org) with an enterprise business
        - 6 private repos with CodeQL-supported languages (Python, JavaScript, Ruby, Go)
        - Repos have recent push activity so they appear as suggested repos

        Note: You must manually enable feature flags (code_security_risk_assessment,
        csra_cooldown_bypass) for the org before using the CSRA UI.

        After running, visit:
          http://<host>/orgs/csra-test-org/security/risk-assessment

        HELP
      end

      def self.run(options = {})
        puts "\n🚀 Setting up CSRA-eligible repositories...\n\n"

        user, org, repos = CsraBase.setup_org_and_repos

        puts "\n"
        puts "✅ CSRA-eligible repositories are ready!\n\n"
        puts "  Organization: #{org.login}"
        puts "  Repositories:"
        repos.each do |repo|
          langs = repo.languages.includes(:language_name).map { |l| l.language_name.name }.join(", ")
          puts "    - #{repo.name} (#{langs})"
        end
        puts "\n  Visit: http://#{GitHub.host_name}/orgs/#{org.login}/security/risk-assessment"
        puts "\n"
      end
    end
  end
end
