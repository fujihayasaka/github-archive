# typed: strict
# frozen_string_literal: true

require_relative "../runner"
require_relative "csra_base"

module Seeds
  class Runner
    class CsraNoVulns < Seeds::Runner
      sig { returns(String) }
      def self.help
        <<~HELP
        Creates a completed CSRA with zero vulnerabilities found.

        Sets up:
        - An organization with eligible repos (same as csra_eligible_repos)
        - A completed assessment where all repos scanned successfully but found no vulnerabilities

        After running, visit:
          http://<host>/orgs/csra-test-org/security/risk-assessment

        HELP
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        puts "\n🚀 Creating a CSRA with zero vulnerabilities...\n\n"

        user, org, repos = CsraBase.setup_org_and_repos

        puts "  🌀 Creating assessment..."
        assessment = CsraBase.create_assessment(org: org, user: user, repos: repos)
        puts "  ✅ Created assessment ##{assessment.number}"

        # Complete each repo without adding any vulnerability results
        repos.each do |repo|
          repo_row = SecurityProductsEnablement::CodeScanningAssessmentRepository
            .find_by!(assessment_id: assessment.id, repository_id: repo.id)
          repo_row.update_column(:status, SecurityProductsEnablement::CodeScanningAssessmentRepository.statuses[:completed])
          puts "  ✅ Completed scan for #{repo.name} (0 vulnerabilities)"
        end

        CsraBase.finalize_assessment_status!(assessment)
        puts "\n"
        puts "✅ Zero-vulnerability CSRA is ready!\n\n"
        puts "  Organization: #{org.login}"
        puts "  Assessment ##{assessment.number} — Status: #{assessment.status}"
        puts "  Repos scanned: #{assessment.assessment_repositories.count}"
        puts "  Total vulnerabilities found: 0"
        puts "\n  Visit: http://#{GitHub.host_name}/orgs/#{org.login}/security/risk-assessment"
        puts "\n"
      end
    end
  end
end
