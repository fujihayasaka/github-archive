# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class PullRequestSHA256Repo < Seeds::Runner
      DEFAULT_USER_LOGIN = "monalisa"
      DEFAULT_ORG_NAME = "github"
      DEFAULT_ORG_REPO_NAME = "github"
      DEFAULT_REPO_NAME = "sha256-smile"

      def self.help
        <<~HELP
        Seed pull requests in SHA-256 repos.

        Options:
          --user, -u
            String name of the pull request user.
            Defaults to #{DEFAULT_USER_LOGIN}.
            Example: bin/seed pull_request_sha256_repo -u octocat
          --nwo, -r
            String "name with owner" of the pull request base repository.
            Defaults to #{DEFAULT_USER_LOGIN}/#{DEFAULT_REPO_NAME}.
            Example: bin/seed pull_request_sha256_repo -r octocat/octorepo
        HELP
      end

      def self.run(options = {})
        merge_queue = options[:merge_queue] || false
        # Ensure given user exists
        user_login = options[:user] || DEFAULT_USER_LOGIN
        puts "Finding or creating PR author #{user_login}..."
        user = Seeds::Objects::User.create(login: user_login)

        repo_nwo = options[:nwo] || "#{user_login}/#{DEFAULT_REPO_NAME}"
        puts "Finding or creating repo #{repo_nwo}..."

        if merge_queue
          ::Seeds::Runner::MergeQueue.execute(sha_256: true)
        else
          repo = Seeds::Objects::Repository.create_with_nwo(
            nwo: repo_nwo,
            setup_master: true,
            is_public: true,
            hash_algorithm: :sha256,
          )

          puts "Creating commits ..."
          branch_suffix = SecureRandom.hex
          puts "Branch suffix: #{branch_suffix}"
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: repo.default_branch,
            message: "Base commit on default branch",
            committer: user,
            files: {
              "README.md" => "# SHA 256!\n",
            }
          )

          # make this a loop with a parameter for the number of PRs to create
          puts "Creating pull requests ..."
          sha256_pr_ref_name = "sha256-branch-#{SecureRandom.hex}"

          Seeds::Objects::Commit.create(
            repo:,
            branch_name: sha256_pr_ref_name,
            from_branch: repo.default_branch,
            message: "Add One.txt",
            committer: user,
            files: {
              "#{branch_suffix}/one.txt" => "ONE",
            }
          )

          ::PullRequest.create_for!(
            repo,
            user:,
            title: "Pull request in SHA-256 repository",
            body: "This pull request is in a repository using SHA-256 object hashing.",
            head: sha256_pr_ref_name,
            base: repo.default_branch,
          )
        end
      end
    end
  end
end
