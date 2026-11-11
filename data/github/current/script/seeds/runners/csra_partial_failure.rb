# typed: true
# frozen_string_literal: true

require_relative "../runner"
require_relative "csra_base"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class CsraPartialFailure < Seeds::Runner
      def self.help
        <<~HELP
        Creates a partially failed CSRA (some repos completed, some failed).

        Sets up:
        - An organization with eligible repos (same as csra_eligible_repos)
        - A completed assessment where 4 repos scanned successfully and 2 failed
        - Vulnerability results for completed repos, failure reasons for failed repos

        After running, visit:
          http://<host>/orgs/csra-test-org/security/risk-assessment

        HELP
      end

      def self.run(options = {})
        puts "\n🚀 Creating a partially failed CSRA...\n\n"

        user, org, repos = CsraBase.setup_org_and_repos

        # Create the assessment
        puts "  🌀 Creating assessment..."
        assessment = CsraBase.create_assessment(org: org, user: user, repos: repos)
        puts "  ✅ Created assessment ##{assessment.number}"

        # Split repos: first 4 succeed, last 2 fail
        successful_repos = repos.first(4)
        failed_repos = repos.last(2)

        # Complete successful repos with vulnerability results
        rules = CsraBase::SAMPLE_RULES
        successful_repos.each_with_index do |repo, i|
          start_idx = i % rules.size
          repo_rules = rules.rotate(start_idx).first(3)
          CsraBase.complete_repo_with_results(assessment, repo, repo_rules)
          puts "  ✅ Completed scan for #{repo.name} (#{repo_rules.size} rules found)"
        end

        # Fail the remaining repos
        failure_reasons = [
          "Analysis timed out after 1 hour",
          "Repository is too large to analyze",
        ]
        failed_repos.each_with_index do |repo, i|
          reason = failure_reasons[i % failure_reasons.size]
          CsraBase.fail_repo(assessment, repo, reason: reason)
          puts "  ❌ Failed scan for #{repo.name}: #{reason}"
        end

        # Explicitly set the final assessment status
        CsraBase.finalize_assessment_status!(assessment)
        completed_count = assessment.assessment_repositories.where(status: :completed).count
        failed_count = assessment.assessment_repositories.where(status: :failed).count
        total_vulns = assessment.assessment_results.sum(:vulnerability_count)

        puts "\n"
        puts "✅ Partially failed CSRA is ready!\n\n"
        puts "  Organization: #{org.login}"
        puts "  Assessment ##{assessment.number} — Status: #{assessment.status}"
        puts "  Repos completed: #{completed_count}/#{repos.size}"
        puts "  Repos failed: #{failed_count}/#{repos.size}"
        puts "  Total vulnerabilities found: #{total_vulns}"
        puts "\n  Visit: http://#{GitHub.host_name}/orgs/#{org.login}/security/risk-assessment"
        puts "\n"
      end
    end
  end
end
