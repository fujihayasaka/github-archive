# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class PullsDashboard < Seeds::Runner
      DEFAULT_AUTHOR = "monalisa"
      DEFAULT_ORG_NAME = "github"
      DEFAULT_ORG_REPO_NAME = "github"
      DEFAULT_REPO_NAME = "smile"
      DEFAULT_REVIEWERS = %w(octocat4 octocat5 octocat6).freeze
      DEFAULT_TEAM_NAME = "pulls-reviewers"

      def self.help
        <<~HELP
        Seed data for the /pulls dashboard and inbox page.

        - Creates baseline PRs via PullRequests and PullRequestReviews runners
        - Creates a review team with members
        - Creates PRs with team review requests and non-approving reviews
        - Adds branch protection (required reviews + required status checks) to github/github
        - Seeds check runs on 3 PRs per repo (all passing, non-required failing, required failing)
        - Creates a merge conflict PR with approved review and passing CI
        - Creates PRs enqueued in the merge queue
        - Repairs Elastomer indexes
        HELP
      end

      def self.run(options = {})
        require_relative "../factory_bot_loader"
        require "#{Rails.root}/test/test_helpers/example_repositories"
        require "#{Rails.root}/test/test_helpers/first_party_apps_helper"
        require "#{Rails.root}/test/test_helpers/machinist_helpers"

        extend GitHub::MachinistHelpers
        author = Seeds::Objects::User.create(login: DEFAULT_AUTHOR)

        # --- Set up repos (user-owned + org-owned) ---
        puts "Setting up repos..."
        user_repo = Seeds::Objects::Repository.create_with_nwo(nwo: "#{DEFAULT_AUTHOR}/#{DEFAULT_REPO_NAME}", setup_master: true, is_public: true)

        org = Seeds::Objects::Organization.create(login: DEFAULT_ORG_NAME, admin: author)
        org_repo = Seeds::Objects::Repository.create_with_nwo(nwo: "#{DEFAULT_ORG_NAME}/#{DEFAULT_ORG_REPO_NAME}", setup_master: true)

        # --- Remove existing branch protection from prior runs so we can push to default branches ---
        [user_repo, org_repo].each do |repo|
          repo.protected_branches.each do |pb|
            puts "Removing existing branch protection on #{repo.nwo}:#{pb.name}..."
            pb.destroy
          end
        end

        # --- Set up reviewers ---
        puts "Setting up reviewers..."
        reviewers = DEFAULT_REVIEWERS.map do |login|
          Seeds::Objects::User.create(login: login)
        end

        all_users = [author] | reviewers
        all_users.each do |user|
          user_repo.add_member(user)
          org.add_member(user)
          org_repo.add_member(user)
        end

        # --- Create review team (org-owned repo only) ---
        puts "Creating review team #{DEFAULT_TEAM_NAME}..."
        team = Seeds::Objects::Team.create!(org: org, name: DEFAULT_TEAM_NAME)
        raise Seeds::Objects::CreateFailed, "Team failed to create" unless team
        team.add_repository(org_repo, :push)
        team.add_member(author)
        reviewers.each { |r| team.add_member(r) }

        # --- Seed baseline PRs ---
        puts "\n=== Seeding baseline pull requests ==="
        Seeds::Runner::PullRequests.execute
        Seeds::Runner::PullRequestReviews.execute

        # --- Set up GitHub Actions app for check runs ---
        app = find_or_create_actions_app([user_repo, org_repo])

        default_files = {
          "README.md" => "# Project\n\n#{Faker::Lorem.paragraphs.join("\n\n")}\n",
          "src/main.rb" => "# Main application\n\n#{Faker::Source.print_1_to_10(lang: :ruby)}",
          "src/helpers.js" => "// Helpers\n\n#{Faker::Source.print_1_to_10(lang: :javascript)}",
          "docs/guide.md" => "# Guide\n\n#{Faker::Lorem.paragraphs.join("\n\n")}\n",
        }

        [user_repo, org_repo].each do |repo|
          is_org_repo = repo.in_organization?
          puts "\n=== Seeding dashboard PRs for #{repo.nwo} ==="

          # Ensure base files exist
          commit_with_retry(
            repo: repo,
            committer: author,
            message: "Add base files for dashboard seeding",
            files: default_files
          )

          # --- PR requiring review with non-approving review + comments ---
          create_pr_needing_review(repo: repo, author: author, reviewers: reviewers, team: is_org_repo ? team : nil)

          # --- Check run PRs (3 per repo) ---
          create_check_run_prs(repo: repo, author: author, reviewer: reviewers.first, app: app)

          # --- Merge conflict PR with approved review + passing CI ---
          create_merge_conflict_pr(repo: repo, author: author, reviewer: reviewers.first, app: app)

          # --- PR with many changed files + approved review + green CI ---
          create_approved_green_pr(repo: repo, author: author, reviewer: reviewers.first, app: app)

          # --- PRs where monalisa is the requested reviewer (authored by someone else) ---
          create_prs_requesting_monalisa(repo: repo, monalisa: author, other_author: reviewers.first, reviewers: reviewers)

          # --- PR with team review from pulls-reviewers (org repo only) ---
          create_pr_with_team_review(repo: repo, author: author, team: team, reviewer: reviewers.second) if is_org_repo

          # --- PRs assigned to monalisa (authored by someone else) ---
          create_prs_assigned_to_monalisa(repo: repo, monalisa: author, other_author: reviewers.second)

        end

        # --- Merge queue PRs ---
        create_merge_queue_prs(repos: [user_repo, org_repo], author: author)

        # --- Branch protection on github/github (must be after all commits to default branch) ---
        setup_branch_protection(repo: org_repo, creator: author)

        # --- Enqueue merge commit creation for all open PRs so MergeStateStatus resolves ---
        puts "\nEnqueuing mergeable updates for open PRs..."
        [user_repo, org_repo].each do |repo|
          repo.pull_requests.joins(:issue).where(issues: { state: "open" }).find_each do |pr|
            pr.enqueue_mergeable_update(priority: :high)
          end
          puts "  Enqueued mergeable updates for #{repo.nwo}"
        end
      end

      # ---- Helper methods ----

      def self.commit_with_retry(retries: 3, repo:, committer:, message:, files:)
        Seeds::Objects::Commit.create(repo: repo, committer: committer, message: message, files: files)
      rescue Git::Ref::ComparisonMismatch => e
        retries -= 1
        if retries > 0
          puts "  Retrying commit due to ComparisonMismatch: #{e.message}"
          retry
        else
          raise
        end
      end

      def self.find_or_create_actions_app(repos)
        name = GitHub.launch_github_app_name
        puts "Finding or creating GitHub Actions app '#{name}'..."
        app = Integration.find_by(name: name)
        if !app.present?
          require_relative "../../create-launch-github-app"
          app = CreateLaunchGitHubApp.new.create_app
        end

        repos.each do |repo|
          puts "Installing app on #{repo.nwo}..."
          installer = repo.owner.organization? ? repo.owner.admins.first : repo.owner
          owner_installation = app.installations_on(repo.owner).first
          if owner_installation.present?
            ::IntegrationInstallation::Editor.append(
              owner_installation,
              repositories: [repo],
              editor: installer,
              entry_point: :seeds_runners_actions_create_and_install_github_app
            )
          else
            app.install_on(
              repo.owner,
              repositories: [repo],
              installer: installer,
              entry_point: :seeds_runners_actions_create_and_install_github_app
            )
          end
        end

        app
      end

      def self.create_pr_needing_review(repo:, author:, reviewers:, team:)
        puts "Creating PR requiring review with non-approving reviews in #{repo.nwo}..."

        head_ref_name = "needs-review-#{SecureRandom.hex}"
        Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: head_ref_name,
          message: "Add feature that needs review",
          files: {
            "src/new_feature.rb" => "# New feature\nclass NewFeature\n  def call\n    puts 'hello'\n  end\nend\n",
            "src/helpers.js" => "// Updated helpers\nfunction helper() { return true; }\n",
          }
        )

        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "feat: Add new feature (needs review)",
          body: "This PR adds a new feature and needs review from the team.\n\n- Added new_feature.rb\n- Updated helpers.js",
          head: head_ref_name,
          base: repo.default_branch,
        )

        # Request review from team (org repos only)
        if team
          pull.review_requests.create!(reviewer: team)
          puts "  Requested review from team @#{team.name}"
        end

        # Request review from individual reviewers
        reviewers.first(2).each do |reviewer|
          next if pull.review_requests.where(reviewer: reviewer).exists?
          pull.review_requests.create!(reviewer: reviewer)
          puts "  Requested review from @#{reviewer.login}"
        end

        # Add a changes_requested review
        puts "  Adding changes_requested review from @#{reviewers[0].login}..."
        Seeds::Objects::PullRequestReview.create(
          pull_request: pull,
          user: reviewers[0],
          state: :changes_requested
        )

        # Add a commented review (non-approving)
        puts "  Adding commented review from @#{reviewers[1].login}..."
        Seeds::Objects::PullRequestReview.create(
          pull_request: pull,
          user: reviewers[1],
          state: :commented
        )

        pull
      end

      def self.create_check_run_prs(repo:, author:, reviewer:, app:)
        puts "Creating PRs with check runs in #{repo.nwo}..."

        # PR 1: All checks passing
        pr_all_pass = create_pr_with_checks(
          repo: repo,
          author: author,
          app: app,
          title: "ci: All checks passing",
          branch_prefix: "ci-all-pass",
          checks: [
            { name: "ci/build", conclusion: :success },
            { name: "ci/test", conclusion: :success },
            { name: "lint", conclusion: :success },
          ]
        )
        puts "  Created PR #{pr_all_pass.number}: all checks passing"

        # PR 2: Non-required check failing, required checks passing + approved review
        pr_non_req_fail = create_pr_with_checks(
          repo: repo,
          author: author,
          app: app,
          title: "ci: Non-required check failing",
          branch_prefix: "ci-lint-fail",
          checks: [
            { name: "ci/build", conclusion: :success },
            { name: "ci/test", conclusion: :success },
            { name: "lint", conclusion: :failure },
          ]
        )
        Seeds::Objects::PullRequestReview.create(pull_request: pr_non_req_fail, user: reviewer, state: :approved)
        puts "  Created PR #{pr_non_req_fail.number}: non-required 'lint' check failing + approved review"

        # PR 3: Required check failing + approved review
        pr_req_fail = create_pr_with_checks(
          repo: repo,
          author: author,
          app: app,
          title: "ci: Required check failing",
          branch_prefix: "ci-build-fail",
          checks: [
            { name: "ci/build", conclusion: :failure },
            { name: "ci/test", conclusion: :success },
            { name: "lint", conclusion: :success },
          ]
        )
        Seeds::Objects::PullRequestReview.create(pull_request: pr_req_fail, user: reviewer, state: :approved)
        puts "  Created PR #{pr_req_fail.number}: required 'ci/build' check failing + approved review"
      end

      def self.create_pr_with_checks(repo:, author:, app:, title:, branch_prefix:, checks:)
        head_ref_name = "#{branch_prefix}-#{SecureRandom.hex}"

        commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: head_ref_name,
          message: "Changes for #{title}",
          files: { "src/#{branch_prefix.tr("-", "_")}.rb" => "# #{title}\nputs 'ok'\n" }
        )

        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: title,
          body: "PR to verify check run states in the dashboard.",
          head: head_ref_name,
          base: repo.default_branch,
        )

        # Create push for check suite
        push = ::Push.create!(
          before: commit.first_parent_oid,
          after: commit.oid,
          ref: "refs/heads/#{head_ref_name}",
          repository_id: repo.id,
          pusher: author,
          pushed_at: Time.current
        )

        # Determine overall suite conclusion from individual checks
        suite_conclusion = checks.any? { |c| c[:conclusion] == :failure } ? :failure : :success

        check_suite = Seeds::Objects::CheckSuite.create(
          repo: repo,
          app: app,
          push: push,
          head_branch: head_ref_name,
          head_sha: push.after,
          attrs: {
            name: "CI",
            status: ::CheckRun.statuses[:completed],
            conclusion: ::CheckRun.conclusions[suite_conclusion],
            event: "push",
            check_runs_rerunnable: false,
            external_id: SecureRandom.uuid,
          }
        )

        checks.each_with_index do |check, idx|
          started_at = Time.current - (rand(2..10)).minutes
          check_suite.check_runs.create!(
            name: check[:name],
            display_name: check[:name],
            status: ::CheckRun.statuses[:completed],
            completed_at: Time.current,
            conclusion: ::CheckRun.conclusions[check[:conclusion]],
            started_at: started_at,
            number: idx + 1,
            repository: repo,
            external_id: SecureRandom.uuid
          )
        end

        pull
      end

      def self.create_merge_conflict_pr(repo:, author:, reviewer:, app:)
        puts "Creating merge conflict PR with approved review + passing CI in #{repo.nwo}..."

        conflict_file = "conflict-target-#{SecureRandom.hex(4)}.md"

        # Add the conflict target file to default branch
        commit_with_retry(
          repo: repo,
          committer: author,
          message: "Add #{conflict_file}",
          files: { conflict_file => "# Original content\n\nThis is the original content.\n" }
        )

        # Record the current default branch OID before we diverge
        default_ref = repo.refs.find("refs/heads/#{repo.default_branch}")
        base_oid = default_ref.target_oid

        # Create head branch from current default branch state
        head_ref_name = "conflict-branch-#{SecureRandom.hex}"
        head_ref = repo.refs.create("refs/heads/#{head_ref_name}", base_oid, author)

        # Make a conflicting change on the head branch
        metadata = { message: "Update #{conflict_file} on feature branch", committer: author, author: author }
        head_commit = head_ref.append_commit(metadata, author) do |changes|
          changes.add(conflict_file, "# Feature branch content\n\nThis is completely different content from the feature branch.\n\nAdded at #{Time.current}\n")
        end

        # Make a different change to the SAME file on default branch (creates conflict)
        commit_with_retry(
          repo: repo,
          committer: author,
          message: "Update #{conflict_file} on default branch (will conflict)",
          files: { conflict_file => "# Default branch content\n\nThis is different content from the default branch.\n\nUpdated at #{Time.current}\n" }
        )

        # Create the PR (will have merge conflicts)
        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "feat: Merge conflict PR with approved review and passing CI",
          body: "This PR has merge conflicts but has been approved and CI is passing.",
          head: head_ref_name,
          base: repo.default_branch,
        )

        # Add approved review
        Seeds::Objects::PullRequestReview.create(
          pull_request: pull,
          user: reviewer,
          state: :approved
        )
        puts "  Added approved review from @#{reviewer.login}"

        # Add passing check suite
        push = ::Push.create!(
          before: head_commit.first_parent_oid,
          after: head_commit.oid,
          ref: "refs/heads/#{head_ref_name}",
          repository_id: repo.id,
          pusher: author,
          pushed_at: Time.current
        )

        check_suite = Seeds::Objects::CheckSuite.create(
          repo: repo,
          app: app,
          push: push,
          head_branch: head_ref_name,
          head_sha: push.after,
          attrs: {
            name: "CI",
            status: ::CheckRun.statuses[:completed],
            conclusion: ::CheckRun.conclusions[:success],
            event: "push",
            check_runs_rerunnable: false,
            external_id: SecureRandom.uuid,
          }
        )

        check_suite.check_runs.create!(
          name: "ci/build",
          display_name: "ci/build",
          status: ::CheckRun.statuses[:completed],
          completed_at: Time.current,
          conclusion: ::CheckRun.conclusions[:success],
          started_at: Time.current - 3.minutes,
          number: 1,
          repository: repo,
          external_id: SecureRandom.uuid
        )

        puts "  Created merge conflict PR ##{pull.number} with approved review + passing CI"
        pull
      end

      def self.create_approved_green_pr(repo:, author:, reviewer:, app:)
        puts "Creating PR with many changed files + approved review + green CI in #{repo.nwo}..."

        head_ref_name = "approved-green-#{SecureRandom.hex}"
        files = {}
        10.times do |i|
          files["src/feature_#{i}.rb"] = "# Feature #{i}\nmodule Feature#{i}\n  def call\n    puts 'feature #{i}'\n  end\nend\n"
        end

        commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: head_ref_name,
          message: "Add multiple feature files",
          files: files
        )

        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "feat: Large PR with approved review and all green CI",
          body: "This PR has many changed files, an approved review, and all CI checks passing.",
          head: head_ref_name,
          base: repo.default_branch,
        )

        # Approved review
        Seeds::Objects::PullRequestReview.create(pull_request: pull, user: reviewer, state: :approved)

        # Green CI
        push = ::Push.create!(
          before: commit.first_parent_oid,
          after: commit.oid,
          ref: "refs/heads/#{head_ref_name}",
          repository_id: repo.id,
          pusher: author,
          pushed_at: Time.current
        )

        check_suite = Seeds::Objects::CheckSuite.create(
          repo: repo,
          app: app,
          push: push,
          head_branch: head_ref_name,
          head_sha: push.after,
          attrs: {
            name: "CI",
            status: ::CheckRun.statuses[:completed],
            conclusion: ::CheckRun.conclusions[:success],
            event: "push",
            check_runs_rerunnable: false,
            external_id: SecureRandom.uuid,
          }
        )

        ["ci/build", "ci/test", "lint"].each_with_index do |check_name, idx|
          check_suite.check_runs.create!(
            name: check_name,
            display_name: check_name,
            status: ::CheckRun.statuses[:completed],
            completed_at: Time.current,
            conclusion: ::CheckRun.conclusions[:success],
            started_at: Time.current - (rand(2..5)).minutes,
            number: idx + 1,
            repository: repo,
            external_id: SecureRandom.uuid
          )
        end

        puts "  Created PR ##{pull.number} with #{files.size} files + approved review + green CI"
        pull
      end

      def self.create_prs_requesting_monalisa(repo:, monalisa:, other_author:, reviewers:)
        puts "Creating PRs where monalisa is the requested reviewer in #{repo.nwo}..."

        2.times do |i|
          head_ref_name = "review-request-monalisa-#{i}-#{SecureRandom.hex}"
          Seeds::Objects::Commit.create(
            repo: repo,
            committer: other_author,
            branch_name: head_ref_name,
            message: "Changes needing monalisa review #{i + 1}",
            files: { "src/needs_review_#{i}.rb" => "# Needs monalisa review\nputs 'please review'\n" }
          )

          pull = ::PullRequest.create_for!(
            repo,
            user: other_author,
            title: "feat: PR requesting review from monalisa (#{i + 1})",
            body: "This PR needs monalisa's review.",
            head: head_ref_name,
            base: repo.default_branch,
          )

          pull.review_requests.create!(reviewer: monalisa)
          puts "  Created PR ##{pull.number} with monalisa as requested reviewer"
        end
      end

      def self.create_pr_with_team_review(repo:, author:, team:, reviewer:)
        puts "Creating PR with team review from #{team.name} in #{repo.nwo}..."

        head_ref_name = "team-reviewed-#{SecureRandom.hex}"
        Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: head_ref_name,
          message: "Changes reviewed by team",
          files: { "src/team_feature.rb" => "# Team reviewed feature\nclass TeamFeature\n  def call\n    puts 'team approved'\n  end\nend\n" }
        )

        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "feat: PR with team review from #{team.name}",
          body: "This PR has been reviewed by the #{team.name} team.",
          head: head_ref_name,
          base: repo.default_branch,
        )

        # Request review from team
        pull.review_requests.create!(reviewer: team)

        # Team member submits an approved review on behalf of the team
        Seeds::Objects::PullRequestReview.create(pull_request: pull, user: reviewer, state: :approved)
        puts "  Created PR ##{pull.number} with team review (approved) from #{team.name}"
        pull
      end

      def self.create_prs_assigned_to_monalisa(repo:, monalisa:, other_author:)
        puts "Creating PRs assigned to monalisa (authored by others) in #{repo.nwo}..."

        2.times do |i|
          head_ref_name = "assigned-to-monalisa-#{i}-#{SecureRandom.hex}"
          Seeds::Objects::Commit.create(
            repo: repo,
            committer: other_author,
            branch_name: head_ref_name,
            message: "Work assigned to monalisa #{i + 1}",
            files: { "src/assigned_work_#{i}.rb" => "# Assigned to monalisa\nputs 'assigned work #{i + 1}'\n" }
          )

          pull = ::PullRequest.create_for!(
            repo,
            user: other_author,
            title: "feat: PR assigned to monalisa (#{i + 1})",
            body: "This PR is assigned to monalisa for tracking.",
            head: head_ref_name,
            base: repo.default_branch,
          )

          pull.issue.add_assignees([monalisa])
          puts "  Created PR ##{pull.number} assigned to monalisa"
        end
      end

      def self.create_merge_queue_prs(repos:, author:)
        puts "\n=== Seeding merge queue PRs ==="

        # Ensure merge queue feature flag is on
        Seeds::Objects::FeatureFlag.enable(feature_flag: "merge_queue")

        # Ensure merge queue system actor exists
        T.unsafe(self).make_trusted_oauth_apps_owner
        Apps::Privileged.integration(:merge_queue) || Apps::Privileged::MergeQueue.seed_database!

        repos.each do |repo|
          puts "Creating merge queue PRs for #{repo.nwo}..."

          # Enable merge queue on the protected branch
          pb = Seeds::Objects::ProtectedBranch.create_for_merge_queue!(
            repo: repo,
            creator: author,
            branch_name: repo.default_branch
          )

          # Create 2 PRs and enqueue them
          2.times do |i|
            branch_ref = repo.refs.find(repo.default_branch)
            pull = Seeds::Objects::PullRequest.create(
              repo: repo,
              committer: author,
              title: "Merge queue PR #{i + 1}: #{Faker::Hacker.say_something_smart}",
              base_ref: branch_ref
            )

            # Enqueue the PR
            unless pull.merge_queue_entry
              pull.create_merge_commit
              merge_queue = repo.merge_queue_for(branch: repo.default_branch)
              FactoryBot.create(:merge_queue_entry, queue: merge_queue, pull_request: pull)
              puts "  Enqueued PR ##{pull.number} in merge queue"
            end
          end
        end
      end

      def self.setup_branch_protection(repo:, creator:)
        puts "\nSetting up branch protection on #{repo.nwo} #{repo.default_branch}..."

        pb = Seeds::Objects::ProtectedBranch.create!(
          repo: repo,
          creator: creator,
          branch_name: repo.default_branch
        )

        # Require pull request reviews
        pb.enable_required_pull_request_reviews(required_approving_review_count: 1)

        # Require status checks
        pb.required_status_checks_enforcement_level = ::ProtectedBranch::LEVELS[:everyone]
        pb.strict_required_status_checks_policy = true

        unless pb.save
          raise Seeds::Objects::CreateFailed, "ProtectedBranch failed to save: #{pb.errors.full_messages.to_sentence}"
        end

        # Add required check context
        unless pb.required_status_checks.find_by(context: "ci/build")
          pb.required_status_checks.create!(context: "ci/build")
          puts "  Added required status check: ci/build"
        end

        puts "  Branch protection configured: required reviews (1) + required status check (ci/build)"
        pb
      end
    end
  end
end
