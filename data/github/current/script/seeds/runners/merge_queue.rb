# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class MergeQueue < Seeds::Runner
      def self.help
        <<~HELP
        Seed repositories set up to use the merge queue.
        HELP
      end

      def self.run(options = {})
        require_relative "../factory_bot_loader"
        require "#{Rails.root}/test/test_helpers/example_repositories"
        require "#{Rails.root}/test/test_helpers/first_party_apps_helper"
        require "#{Rails.root}/test/test_helpers/machinist_helpers"

        include GitHub::MachinistHelpers

        new.run(options)
      end

      def run(options)
        Seeds::Objects::FeatureFlag.enable(feature_flag: "merge_queue")
        puts "\n"

        system_actor
        merge_queue_repo
        merge_queue_repo_like_github_github

        puts "Finished merge queue seeds!"
      end

      private

      def system_actor
        return @system_actor if @system_actor
        T.unsafe(self).make_trusted_oauth_apps_owner
        @system_actor = Apps::Privileged.integration(:merge_queue) || Apps::Privileged::MergeQueue.seed_database!
      end

      def monalisa
        @monalisa ||= Seeds::Objects::User.monalisa
      end

      def repo_member
        return @repo_member if @repo_member
        login = "repo-member"
        @repo_member = User.find_by_login(login)
        unless @repo_member
          puts "Creating user to be a non-admin repository member, #{login}"
          @repo_member = Seeds::Objects::User.create(login: login, email: "#{login}@example.com")
        end
        @repo_member
      end

      def merge_queue_repo
        repo = repo_for(user: monalisa, name: "merge-queue")
        add_repo_member(repo: repo, user: repo_member)
        protected_branch_name = repo.default_branch
        Seeds::Objects::ProtectedBranch.create_for_merge_queue!(repo: repo, creator: monalisa,
          branch_name: protected_branch_name)
        pull = pull_request_for(user: monalisa, repo: repo, branch_name: protected_branch_name)
        enqueue_pull_request(pull)
        puts "\n"
      end

      def merge_queue_repo_like_github_github
        repo = repo_for(user: monalisa, name: "merge-queue-github-github")
        repo.enable_feature_flag(:merge_queue_extra_branch_protection_settings)
        repo.enable_feature_flag(:merge_queue_uses_queue_refs)
        repo.enable_feature_flag(:merge_queue_deploy_then_merge)
        add_repo_member(repo: repo, user: repo_member)
        protected_branch_name = repo.default_branch
        protected_branch = Seeds::Objects::ProtectedBranch.create_for_merge_queue!(repo: repo, creator: monalisa,
          branch_name: protected_branch_name)
        5.times do
          pull = pull_request_for(user: monalisa, repo: repo, branch_name: protected_branch_name)
          enqueue_pull_request(pull)
          puts "\n"
        end
      end

      def repo_for(user:, name:)
        repo = user.repositories.find_by(name: name)
        unless repo
          puts "Creating #{user}/#{name} repository"
          repo = Seeds::Objects::Repository.create(owner_name: user.login, repo_name: name, setup_master: true)
        end
        repo
      end

      def add_repo_member(repo:, user:)
        unless repo.member?(user)
          puts "Adding #{user} to #{repo.nwo}"
          repo.add_member(user)
        end
      end

      def pull_request_for(user:, repo:, branch_name:)
        puts "Creating a pull request from #{user} to #{repo.nwo} #{branch_name}"
        branch_ref = repo.refs.find(branch_name)
        pull = Seeds::Objects::PullRequest.create(repo: repo, committer: user,
          title: Faker::Hacker.say_something_smart, base_ref: branch_ref)
        pull_url = UrlHelpers.show_pull_request_url(
          user_id: repo.owner_display_login, repository: repo.name, id: pull.number, protocol: GitHub.scheme,
          host: GitHub.host_name, port: codespaces_port,
        )
        puts "Pull request URL: #{pull_url}"
        pull
      end

      def enqueue_pull_request(pull_request)
        queue_entry = pull_request.merge_queue_entry

        unless queue_entry
          pull_request.create_merge_commit

          branch_name = pull_request.base_ref_name
          repo = pull_request.repository
          merge_queue = repo.merge_queue_for(branch: branch_name)

          puts "Creating a merge queue entry for PR ##{pull_request.number} in #{repo.nwo} #{branch_name}"
          queue_entry = FactoryBot.create(:merge_queue_entry, queue: merge_queue, pull_request: pull_request)
        end

        queue_entry
      end

      def deployment_for(user:, env_name:, repo:, pull:)
        puts "Creating a pending deployment to #{env_name} for #{repo.nwo} from #{pull.head_ref}"
        deployment = FactoryBot.create(:deployment, repository: repo, creator: user, environment: env_name,
          sha: pull.head_sha)
        deployment.statuses.create!(creator: user, state: "pending")
        puts "Deployment ID: #{deployment.id}"
        deployment
      end

      def codespaces_port
        return unless ENV["CODESPACES"]
        return @codespaces_port if defined?(@codespaces_port)
        web_tunnel = JSON.parse(File.read(T.must(ENV["GITHUG_WEB_TUNNEL_PATH"])))
        @codespaces_port = web_tunnel["port"]
      rescue TypeError, JSON::ParserError, Errno::ENOENT
        @codespaces_port = nil
      end
    end
  end
end
