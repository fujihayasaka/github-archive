# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class RuleInsightsPermissions < Seeds::Runner
      include ReposSecurityBase

      ORG_NAME = "insights-perms-org"
      REPO_NAME = "insights-perms-repo"
      BIZ_NAME = "insights-perms-enterprise"

      sig { override.returns(String) }
      def org_name
        ORG_NAME
      end

      sig { override.returns(String) }
      def repo_name
        REPO_NAME
      end

      sig { returns(String) }
      def self.help
        <<~HELP
        Seeds test data for verifying that rule insights links are gated by
        user permissions. Creates:
          - An enterprise (business) with an org and repo
          - Rulesets at repo, org, and enterprise levels
          - Rule suites with rule runs tied to each ruleset
          - An admin user (monalisa) and a non-admin contributor

        Use `-f` (force) flag to recreate from scratch.
        HELP
      end

      sig { override.returns(T::Array[Symbol]) }
      def feature_flags
        [:rule_insights_dashboard, :rule_insights_dashboard_org, :rule_insights_clickable, :rules_insights_stafftools_branches, :rules_insights_filter_bar_created]
      end

      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def self.run(options = {})
        new.run(options)
      end

      # Override to create a private repo (public repos cannot have push rulesets)
      sig { override.params(options: T::Hash[Symbol, T.untyped]).void }
      def initialize_repo(options = {})
        if options[:force]
          existing_org = Organization.find_by(login: org_name)
          if existing_org
            fancy_puts "Deleting existing #{repo_name} repo", :loading, indent: 1
            existing_org.repositories.find_by(name: repo_name)&.destroy!
            fancy_puts "Deleted existing #{repo_name} repo", :success, indent: 1
            fancy_puts "Deleting existing #{org_name} org", :loading, indent: 1
            existing_org.destroy!
            ReservedLogin.untombstone!(org_name)
            fancy_puts "Deleted existing #{org_name} org", :success, indent: 1
          end
        end

        repos_security_org = Organization.find_by(login: org_name)
        if repos_security_org.nil?
          fancy_puts "Creating organization: #{org_name}", :loading, indent: 1
          repos_security_org = Seeds::Objects::Organization.create(login: org_name, admin: user)
          fancy_puts "Created organization: #{org_name}", :success, indent: 1
        else
          fancy_puts "Organization #{repos_security_org.login} already exists", :info, indent: 1
        end

        repo = create_repo_if_not_exists(name: repo_name, owner: repos_security_org, is_public: false)

        # Ensure the repo is private (may have been created public in a prior run)
        if repo.public?
          fancy_puts "Making repository private (push rulesets require private repos)", :loading, indent: 1
          repo.update!(public: false)
          fancy_puts "Repository is now private", :success, indent: 1
        end

        seed_repo(repo, repos_security_org, options)
      end

      sig { override.params(repo: Repository, org: Organization, options: T::Hash[Symbol, T.untyped]).void }
      def seed_repo(repo, org, options = {})
        admin = user # monalisa, who is org admin
        contributor = User.find_by(login: "insights-contributor") || Seeds::Objects::User.create(login: "insights-contributor")
        org.add_member(contributor) unless org.member?(contributor)
        # Make contributor a repo admin so they can see insights, but they won't have org/enterprise admin
        repo.add_member(contributor, action: :admin)

        # Create enterprise and add the org to it
        fancy_puts "Setting up enterprise: #{BIZ_NAME}", :loading, indent: 1
        existing_biz = Business.find_by(name: BIZ_NAME)
        if options[:force] && existing_biz
          existing_biz.destroy!
          existing_biz = nil
        end
        business = existing_biz || Seeds::Objects::Business.create(owner: admin, name: BIZ_NAME)
        business.add_organization(org) unless business.organizations.include?(org)
        fancy_puts "Enterprise ready", :success, indent: 1

        # Create rulesets at each level
        fancy_puts "Creating rulesets at repo, org, and enterprise level", :loading, indent: 1

        repo_ruleset = find_or_create_ruleset(
          source: repo,
          name: "Repo-level push policy",
          target: :push,
          enforcement: :enabled
        )

        org_ruleset = find_or_create_ruleset(
          source: org,
          name: "Org-level push policy",
          target: :push,
          enforcement: :enabled
        )
        Seeds::Objects::Ruleset.add_repo_condition(org_ruleset, repo) unless org_ruleset.conditions.any?

        biz_ruleset = find_or_create_ruleset(
          source: business,
          name: "Enterprise-level push policy",
          target: :push,
          enforcement: :enabled
        )
        # Enterprise rulesets need an org condition to be discoverable from the repo context
        unless biz_ruleset.conditions.any?
          biz_ruleset.upsert_conditions([{
            target: "organization_name",
            parameters: { exclude: [], include: [org.login] }
          }])
        end

        fancy_puts "Rulesets created", :success, indent: 1

        # Add rules to each ruleset so they actually evaluate something
        [repo_ruleset, org_ruleset, biz_ruleset].each do |ruleset|
          Seeds::Objects::Ruleset.block_file_extensions(ruleset, ["*.exe"]) if ruleset.rule_configurations.empty?
        end

        # Create rule suites with rule runs pointing to each ruleset
        fancy_puts "Creating rule suites with rule runs", :loading, indent: 1

        rulesets_with_sources = [
          { ruleset: repo_ruleset, sources: [repo] },
          { ruleset: org_ruleset, sources: [repo, org] },
          { ruleset: biz_ruleset, sources: [repo, org, business] },
        ]

        [admin, contributor].each do |committer|
          rulesets_with_sources.each do |config|
            ruleset = config[:ruleset]
            sources = config[:sources]

            3.times do |i|
              run_result = [:allowed, :failed, :failed][i % 3]
              suite_result = [:allowed, :failed, :bypassed][i % 3]

              rule_run = RuleEngine::RuleRun.new(
                rule_type: "file_extension_restriction",
                result: run_result,
                rule_provider_id: ruleset.id,
                rule_provider: "repository_ruleset",
                message: run_result == :failed ? "Changes include a file with a restricted extension: test.exe" : nil,
              )

              ref_update = Git::Ref::Update.new(
                repository: repo,
                before_oid: "0" * 40,
                after_oid: SecureRandom.hex(20),
                refname: "refs/heads/main",
                fast_forward: nil
              )

              suite = RuleEngine::RuleSuite.for_ref_update(
                ref_update: ref_update,
                rule_runs: [rule_run],
                result: suite_result,
                actor: committer
              )
              suite.created_at = (6 - i).days.ago
              suite.save!

              # Create source results so dashboard queries work at every level
              sources.each do |source|
                RuleEngine::RuleSuiteSourceResult.create!(
                  rule_suite: suite,
                  source: source,
                  result: T.must(suite_result),
                  evaluate_result: :none,
                )
              end
            end
          end
        end

        fancy_puts "Rule suites created", :success, indent: 1

        if Rails.env.development?
          puts <<~INSTRUCTIONS

          ============================================================
          TESTING INSTRUCTIONS: Rule Insights Permission Gating
          ============================================================

          ADMIN USER (monalisa, has edit permissions):
            Repo insights:       http://github.localhost/#{org.login}/#{repo.name}/settings/rules/insights
            Org insights:        http://github.localhost/organizations/#{org.login}/settings/rules/insights
            Enterprise insights: http://github.localhost/enterprises/#{business.slug}/settings/rules/insights

            Expected: Clicking a ruleset name should link to the EDIT page.

          NON-ADMIN USER (insights-contributor, does NOT have edit permissions):
            Log in as: insights-contributor
            Repo insights:       http://github.localhost/#{org.login}/#{repo.name}/settings/rules/insights
            Org insights:        http://github.localhost/organizations/#{org.login}/settings/rules/insights

            Expected: Clicking a ruleset name should link to the READ-ONLY
                      view page (not the edit page), and should NOT 404.

          To log in as a different user, visit:
            http://github.localhost/-/login?login=insights-contributor

          ============================================================
          INSTRUCTIONS
        end
      end

      private

      sig do
        params(
          source: RuleEngine::Types::RuleSource,
          name: String,
          target: Symbol,
          enforcement: Symbol,
          target_all: T::Boolean,
        ).returns(RepositoryRuleset)
      end
      def find_or_create_ruleset(source:, name:, target:, enforcement:, target_all: false)
        existing = source.rulesets.find_by(name: name)
        return existing if existing

        Seeds::Objects::Ruleset.create(
          source: source,
          name: name,
          target: target,
          enforcement: enforcement,
          target_all: target_all
        )
      end
    end
  end
end
