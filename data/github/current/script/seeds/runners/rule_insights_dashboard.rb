# typed: strict
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class RuleInsightsDashboard < Seeds::Runner
      include ReposSecurityBase

      sig { override.returns(String) }
      def org_name
        "repos-security"
      end

      sig { override.returns(String) }
      def repo_name
        "insights-dashboard"
      end

      sig { returns(String) }
      def self.help
        <<~HELP
        - Seeds a pre-made repo with historical commits and exemption requests.
        Use `-f` (force) flag to recreate the org and repo.
        HELP
      end

      sig { override.returns(T::Array[Symbol]) }
      def feature_flags
        [:rule_insights_dashboard, :rule_insights_dashboard_org, :rules_insights_filter_bar, :rule_insights_clickable, :rules_insights_stafftools_branches, :rules_insights_filter_bar_created]
      end

      sig { params(options: Options).void }
      def self.run(options = {})
        new.run(options)
      end

      sig { override.params(repo: Repository, org: Organization, options: Options).void }
      def seed_repo(repo, org, options = {})
        repos_contributor_1 = Seeds::Objects::User.create(login: "reposcontributor1")
        repos_contributor_2 = Seeds::Objects::User.create(login: "reposcontributor2")

        org.add_member(repos_contributor_1)

        org.add_member(repos_contributor_2)

        fancy_puts "Creating commits", :loading, indent: 1

        fancy_puts "for #{user.display_login}", :info, indent: 2
        create_commit_history(committer: user, repo:, from: 1.month.ago)
        fancy_puts "for #{repos_contributor_1.display_login}", :info, indent: 2
        create_commit_history(committer: repos_contributor_1, repo:, from: 1.month.ago)
        fancy_puts "for #{repos_contributor_2.display_login}", :info, indent: 2
        create_commit_history(committer: repos_contributor_2, repo:, from: 1.month.ago)

        fancy_puts "Created commits", :success, indent: 1
      end

      sig { params(committer: User, repo: Repository, branch: T.nilable(String), from: T.nilable(Time), to: T.nilable(Time)).void }
      def create_commit_history(committer:, repo:, branch: nil, from: 3.months.ago, to: Time.now)
        from = T.cast(from, Time).to_date
        to = T.cast(to, Time).to_date

        (from..to).each do |date|
          (0..5).each do
            commit = Seeds::Objects::Commit.create(
              committer:,
              repo:,
              branch_name: branch || repo.default_branch,
              files: {
                "dummy-file.txt" => random_string(63)
              },
              message: "create a dummy file",
              date: date.to_time.iso8601,
              from_branch: "main",
            )
            ref_update = Git::Ref::Update.new(
              repository: repo,
              before_oid: "487dd9066dea11516315f8b060654127c2cc832e",
              after_oid: "487dd9066dea11516315f8b060654127c2cc832e",
              refname: "refs/heads/main",
              fast_forward: nil
            )
            enum = rand(6)
            result = :allowed if enum < 4
            result = :failed if enum == 4
            result = :bypassed if enum == 5
            rs = RuleEngine::RuleSuite.for_ref_update(ref_update:, rule_runs: [], result:, actor: committer)
            rs.created_at = date.to_time
            rs.save!

            # Create source results so the dashboard queries (which use source_result_exists) return data.
            # We create one for the repo source and one for the org source so both repo and org dashboards work.
            [repo, repo.owner].each do |source|
              RuleEngine::RuleSuiteSourceResult.create!(
                rule_suite: rs,
                source: source,
                result: T.must(result),
                evaluate_result: :none,
              )
            end

            Exemptions::ExemptionRequest.create!(
              resource_owner: rs,
              requester: committer,
              resource_identifier: rs.after_oid,
              repository: rs.repository,
              request_type: "push_ruleset_bypass",
              created_at: date.to_time,
              expires_at: (date + 7.days).to_time,
            ) if enum < 3
          end
        end
      end
    end
  end
end
