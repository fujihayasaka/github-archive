# typed: true
# frozen_string_literal: true

require_relative "../runner"
require_relative "csra_base"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CsraSuccessful < Seeds::Runner
      def self.help
        <<~HELP
        Creates a completely successful CSRA (all repos completed with results).

        Sets up:
        - An organization with eligible repos (same as csra_eligible_repos)
        - A completed assessment where all 6 repos scanned successfully
        - Vulnerability results across multiple languages and severities

        After running, visit:
          http://<host>/orgs/csra-test-org/security/risk-assessment

        HELP
      end

      def self.run(options = {})
        puts "\n🚀 Creating a completely successful CSRA...\n\n"

        user, org, repos = CsraBase.setup_org_and_repos

        # Create the assessment
        puts "  🌀 Creating assessment..."
        assessment = CsraBase.create_assessment(org: org, user: user, repos: repos)
        puts "  ✅ Created assessment ##{assessment.number}"

        # Complete each repo with vulnerability results
        rules = CsraBase::SAMPLE_RULES
        repos.each_with_index do |repo, i|
          # Give each repo a different subset of rules for variety
          start_idx = i % rules.size
          repo_rules = rules.rotate(start_idx).first(3)
          CsraBase.complete_repo_with_results(assessment, repo, repo_rules)
          puts "  ✅ Completed scan for #{repo.name} (#{repo_rules.size} rules found)"
        end

        # Explicitly set the final assessment status
        CsraBase.finalize_assessment_status!(assessment)
        puts "\n"
        puts "✅ Successful CSRA is ready!\n\n"
        puts "  Organization: #{org.login}"
        puts "  Assessment ##{assessment.number} — Status: #{assessment.status}"
        puts "  Repos scanned: #{assessment.assessment_repositories.count}"
        total_vulns = assessment.assessment_results.sum(:vulnerability_count)
        puts "  Total vulnerabilities found: #{total_vulns}"
        puts "\n  Visit: http://#{GitHub.host_name}/orgs/#{org.login}/security/risk-assessment"
        puts "\n"
      end
    end
  end
end
