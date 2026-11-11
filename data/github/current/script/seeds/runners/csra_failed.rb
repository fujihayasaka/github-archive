# typed: true
# frozen_string_literal: true

require_relative "../runner"
require_relative "csra_base"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CsraFailed < Seeds::Runner
      def self.help
        <<~HELP
        Creates a completely failed CSRA (all repos failed).

        Sets up:
        - An organization with eligible repos (same as csra_eligible_repos)
        - A failed assessment where all 6 repos failed with error reasons

        After running, visit:
          http://<host>/orgs/csra-test-org/security/risk-assessment

        HELP
      end

      FAILURE_REASONS = [
        "Analysis timed out after 1 hour",
        "Repository is too large to analyze",
        "No supported languages detected during analysis",
        "Internal error during CodeQL analysis",
        "Failed to checkout repository",
        "Analysis worker unavailable",
      ].freeze

      def self.run(options = {})
        puts "\n🚀 Creating a completely failed CSRA...\n\n"

        user, org, repos = CsraBase.setup_org_and_repos

        # Create the assessment
        puts "  🌀 Creating assessment..."
        assessment = CsraBase.create_assessment(org: org, user: user, repos: repos)
        puts "  ✅ Created assessment ##{assessment.number}"

        # Fail each repo with a different failure reason
        repos.each_with_index do |repo, i|
          reason = FAILURE_REASONS[i % FAILURE_REASONS.size]
          CsraBase.fail_repo(assessment, repo, reason: reason)
          puts "  ❌ Failed scan for #{repo.name}: #{reason}"
        end

        # Explicitly set the final assessment status
        CsraBase.finalize_assessment_status!(assessment)
        puts "\n"
        puts "✅ Failed CSRA is ready!\n\n"
        puts "  Organization: #{org.login}"
        puts "  Assessment ##{assessment.number} — Status: #{assessment.status}"
        puts "  Repos failed: #{assessment.assessment_repositories.where(status: :failed).count}/#{repos.size}"
        puts "\n  Visit: http://#{GitHub.host_name}/orgs/#{org.login}/security/risk-assessment"
        puts "\n"
      end
    end
  end
end
