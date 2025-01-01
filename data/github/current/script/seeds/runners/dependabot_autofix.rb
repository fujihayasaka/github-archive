# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class DependabotAutofix < Seeds::Runner
      def self.help
        <<~HELP
        Create a Dependabot generated pull request and suggested fix for Dependabot Autofix development
        HELP
      end

      def self.run(options = {})
        owner_name = nil
        repository_name = nil

        if options[:repo]
          parts = options[:repo].split("/", 2)
          if parts.size == 2
            owner_name, repository_name = parts
          else
            repository_name = parts[0]
          end
        end

        if options[:org]
          if owner_name && owner_name != options[:org]
            abort "Organization mismatch! #{owner_name} != #{options[:org]}"
          end

          owner_name = options[:org]
        end

        runner = new(owner_name:, repository_name:)

        puts "Starting..."
        puts

        runner.ensure_owner
        puts "✅ Owner: #{runner.owner.display_login}"

        runner.ensure_repository
        puts "✅ Repository: #{runner.repository.nwo}"

        runner.create_pull_request
        puts "✅ PR: ##{runner.pull_request.number}"

        runner.create_annotations
        puts "👍 Created annotations"

        puts
        puts "PR is ready:\n"
        puts "    http://#{GitHub.host_name}/#{runner.repository.nwo}/pull/#{runner.pull_request.number}"
        puts
      end

      attr_reader :owner_name, :repository_name
      attr_reader :owner, :repository, :pull_request, :new_alert
      attr_reader :unique_identifier

      def initialize(owner_name: nil, repository_name: nil)
        @owner_name = owner_name
        @repository_name = repository_name
      end

      def ensure_owner
        # Ensure monalisa is created before looking up the owner
        _ = Seeds::Objects::User.monalisa

        @owner = if owner_name
          ::User.find_by(login: owner_name) || Seeds::Objects::Organization.create(login: owner_name, admin: Seeds::Objects::User.monalisa)
        else
          Seeds::Objects::Organization.github
        end

        if owner.organization?
          if owner.business.present?
            owner.business.mark_advanced_security_as_purchased_for_entity(actor: owner.admins.first)
          else
            owner.mark_advanced_security_as_purchased_for_entity(actor: owner.admins.first)
          end
        end
      end

      def ensure_repository
        @repository = Seeds::Objects::Repository.restore_premade_repo(
          location_premade_git: "test/fixtures/git/examples/dependabot_autofix.git",
          owner_name: owner.display_login,
          repo_name: repository_name || "autofix-demo-#{Time.now.to_i}",
        )

        # Restoring a premade repo will in some cases not have the default branch loaded in the call to `@repo.refs`.
        # Reloading resolves this issue.
        repository.reload
        # dependabot_on_actions is the "parent" FF required for the dependabot_autofix FF to work!!
        repository.enable_dependabot_on_actions(actor: owner.admins.first)
        repository.enable_dependabot_autofix(actor: owner.admins.first)

        if owner.organization?
          repository.enable_advanced_security(actor: owner.admins.first)
        end
      end

      def create_pull_request
        # before_oid = repository.default_branch_ref.commit.oid
        # branch = "dependabot/npm_and_yarn/lodash-example/lodash-4.17.21-#{unique_identifier}"

        @pull_request = ::PullRequest.create_for!(
          repository,
          user: Seeds::Objects::User.monalisa,
          title: "Bumps lodash from 3.0.0 to 4.17.21.",
          body: "Example from https://github.com/dsp-testing/dependabot-breaking-change-test-01",
          head: "dependabot/npm_and_yarn/lodash-example/lodash-4.17.21",
          base: repository.default_branch
        )
      end

      # Create a check suite
      def create_dependabot_check_suite(repository:, head_sha:, github_app_id:)
        check_suite = ::Checks.domain.check_suites.find_or_create(
          repo: repository,
          head_sha: head_sha,
          github_app_id: github_app_id,
        )
        check_suite
      end

      # Create a check run
      def create_dependabot_check_run(check_suite:, name:, repository:)
        if check_suite.present?
          check_run = check_suite.check_runs.create!(
            name: name,
            repository: check_suite.repository,
            status: "in_progress",
            conclusion: nil
          )
        end
      end

      def create_annotations
        Seeds::Objects::Integration.create_dependabot_integration

        commit_oid = pr_head.commit.oid
        @check_suite = create_dependabot_check_suite(
          head_sha: commit_oid,
          github_app_id: Apps::Privileged.integration_id(:dependabot),
          repository: repository,
        )

        @check_run = create_dependabot_check_run(
          check_suite: @check_suite,
          name: PullRequest::DependabotDependency::CHECK_RUN_NAME,
          repository: repository,
        )

        @annotation_location = {
          file_path: "lodash-example/package.json",
          start_line: 12,
          end_line: 12,
          start_column: 1,
          end_column: 1
        }

        CreateDependabotAnnotationsJob.perform_now(
          check_run_id: @check_run.id,
          pull_request_number: @pull_request.number,
          autofix_job_id: 2343445,
          level: "failure",
          message: "DependaBot failed to update the dependency",
          annotation_location: @annotation_location,
          reason: :forced_by_seed_script
        )
      end

      private

      def pr_base
        repository.heads.find(pull_request.base_ref)
      end

      def pr_head
        repository.heads.find(pull_request.head_ref)
      end
    end
  end
end
