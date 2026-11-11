# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    module CsraBase
      ORG_NAME = "csra-test-org"
      REPO_LANGUAGES = %w[Python JavaScript Ruby Go].freeze
      NUM_REPOS = 6

      def self.find_or_create_user
        Seeds::Objects::User.monalisa
      end

      def self.find_or_create_org(user)
        org = ::Organization.find_by(login: ORG_NAME)
        if org
          puts "  ℹ️  Organization #{ORG_NAME} already exists"
          return org
        end

        puts "  🌀 Creating organization: #{ORG_NAME}"
        org = Seeds::Objects::Organization.create(login: ORG_NAME, admin: user)
        puts "  ✅ Created organization: #{ORG_NAME}"
        org
      end

      def self.find_or_create_business(org, user)
        biz = org.business
        if biz
          puts "  ℹ️  Business already exists for #{ORG_NAME}"
          return biz
        end

        puts "  🌀 Creating business for #{ORG_NAME}"
        biz = Seeds::Objects::Business.create(name: "#{ORG_NAME}-enterprise", owner: user, organizations: [org])
        puts "  ✅ Created business"
        biz
      end

      def self.ensure_language_names
        REPO_LANGUAGES.map do |lang|
          ln = LanguageName.find_by(name: lang) || LanguageName.create!(name: lang)
          puts "  ℹ️  Language: #{lang} (id=#{ln.id})"
          ln
        end
      end

      # Creates private repos with CodeQL-supported languages for the org.
      # Returns the array of created/found repositories.
      def self.find_or_create_eligible_repos(org, language_names)
        repos = []

        NUM_REPOS.times do |i|
          repo_name = "csra-repo-#{i + 1}"
          repo = Repository.find_by(owner_login: org.login, name: repo_name)

          if repo
            puts "  ℹ️  Repository #{repo_name} already exists"
          else
            puts "  🌀 Creating private repository: #{repo_name}"
            repo = Seeds::Objects::Repository.create(
              repo_name: repo_name,
              owner_name: org.login,
              setup_master: true,
              is_public: false,
            )
            puts "  ✅ Created repository: #{repo_name}"
          end

          # Make sure the repo has been pushed recently (for suggested repos)
          repo.update_columns(pushed_at: rand(1..30).days.ago) if repo.pushed_at.nil? || repo.pushed_at < 90.days.ago

          # Add a language to the repo if it doesn't already have one
          lang = language_names[i % language_names.size]
          unless Language.exists?(repository: repo, language_name: lang)
            Language.create!(repository: repo, language_name: lang, size: rand(5000..50000))
            puts "  ✅ Added language #{lang.name} to #{repo_name}"
          end

          repos << repo
        end

        repos
      end

      def self.setup_org_and_repos
        user = find_or_create_user
        org = find_or_create_org(user)
        find_or_create_business(org, user)
        language_names = ensure_language_names
        repos = find_or_create_eligible_repos(org, language_names)
        [user, org, repos]
      end

      # Creates an assessment with repo rows directly in the database (bypassing jobs).
      # Returns the assessment record.
      def self.create_assessment(org:, user:, repos:, number: nil)
        assessment_number = number || SecurityProductsEnablement::CodeScanningAssessment
          .where(owner_id: org.id)
          .maximum(:number)
          .to_i + 1

        assessment = SecurityProductsEnablement::CodeScanningAssessment.create!(
          owner_id: org.id,
          requested_by_id: user.id,
          number: assessment_number,
          status: :pending,
        )

        repos.each do |repo|
          SecurityProductsEnablement::CodeScanningAssessmentRepository.create!(
            assessment: assessment,
            repository_id: repo.id,
            status: :pending,
          )
        end

        assessment
      end

      # Sample vulnerability rules for seed data
      SAMPLE_RULES = [
        { rule_id: "py/sql-injection", rule_name: "SQL Injection", language: "Python", severity: "critical", autofix_supported: true },
        { rule_id: "js/xss", rule_name: "Cross-site Scripting", language: "JavaScript", severity: "high", autofix_supported: true },
        { rule_id: "rb/code-injection", rule_name: "Code Injection", language: "Ruby", severity: "critical", autofix_supported: false },
        { rule_id: "py/path-injection", rule_name: "Path Injection", language: "Python", severity: "high", autofix_supported: true },
        { rule_id: "js/prototype-pollution", rule_name: "Prototype Pollution", language: "JavaScript", severity: "medium", autofix_supported: false },
        { rule_id: "go/sql-injection", rule_name: "SQL Injection", language: "Go", severity: "critical", autofix_supported: true },
        { rule_id: "rb/unsafe-deserialization", rule_name: "Unsafe Deserialization", language: "Ruby", severity: "high", autofix_supported: true },
        { rule_id: "py/hardcoded-credentials", rule_name: "Hardcoded Credentials", language: "Python", severity: "medium", autofix_supported: false },
        { rule_id: "js/insecure-randomness", rule_name: "Insecure Randomness", language: "JavaScript", severity: "low", autofix_supported: true },
        { rule_id: "go/open-redirect", rule_name: "Open Redirect", language: "Go", severity: "medium", autofix_supported: false },
      ].freeze

      # Applies results to a repo row and marks it completed.
      # Uses direct creates and save! to work reliably within test transactions.
      def self.complete_repo_with_results(assessment, repo, rules_subset)
        rules_subset.each_with_index do |rule, idx|
          SecurityProductsEnablement::CodeScanningAssessmentResult.create!(
            assessment_id: assessment.id,
            repository_id: repo.id,
            rule_id: rule.fetch(:rule_id),
            rule_name: rule.fetch(:rule_name),
            language: rule.fetch(:language),
            severity: rule.fetch(:severity),
            autofix_supported: rule.fetch(:autofix_supported, false),
            vulnerability_count: idx + 1,
          )
        end

        repo_row = SecurityProductsEnablement::CodeScanningAssessmentRepository
          .find_by!(assessment_id: assessment.id, repository_id: repo.id)
        repo_row.update_column(:status, SecurityProductsEnablement::CodeScanningAssessmentRepository.statuses[:completed])
      end

      # Fails a repo row with a reason.
      def self.fail_repo(assessment, repo, reason: "Analysis timed out")
        repo_row = SecurityProductsEnablement::CodeScanningAssessmentRepository
          .find_by!(assessment_id: assessment.id, repository_id: repo.id)
        repo_row.update_columns(
          status: SecurityProductsEnablement::CodeScanningAssessmentRepository.statuses[:failed],
          failure_reason: reason,
        )
      end

      # Sets the final assessment status directly based on repo row statuses.
      # Bypasses callbacks for reliability in seed/test environments.
      def self.finalize_assessment_status!(assessment)
        repos = assessment.assessment_repositories.reload

        new_status = if repos.all? { |r| r.status == "failed" }
          :failed
        elsif repos.all? { |r| r.status == "completed" }
          :completed
        elsif repos.any? { |r| r.status == "completed" }
          :completed
        else
          :pending
        end

        assessment.update_columns(status: SecurityProductsEnablement::CodeScanningAssessment.statuses[new_status], updated_at: Time.current)
        assessment.reload
      end
    end
  end
end
