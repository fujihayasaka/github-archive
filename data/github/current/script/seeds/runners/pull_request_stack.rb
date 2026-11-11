# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class PullRequestStack < Seeds::Runner
      DEFAULT_USER_LOGIN = "monalisa"
      DEFAULT_ORG_NAME = "github"
      DEFAULT_ORG_REPO_NAME = "github"
      DEFAULT_REPO_NAME = "smile"

      def self.help
        <<~HELP
        Seed a stack of three PRs.

        Options:
          --user, -u
            String name of the pull request user.
            Defaults to #{DEFAULT_USER_LOGIN}.
            Example: bin/seed pull_request_stack -u octocat
          --nwo, -r
            String "name with owner" of the pull request base repository.
            Defaults to #{DEFAULT_USER_LOGIN}/#{DEFAULT_REPO_NAME}.
            Example: bin/seed pull_request_stack -r octocat/octorepo
        HELP
      end

      def self.run(options = {})
        user_login = options[:user] || DEFAULT_USER_LOGIN
        repo_nwo = options[:nwo] || "#{user_login}/#{DEFAULT_REPO_NAME}"
        puts "\nSeeding pull request stack in #{repo_nwo}..."

        # Ensure given user exists
        puts "Finding or creating PR user #{user_login}..."
        user = Seeds::Objects::User.create(login: user_login)

        # Ensure given repo exists
        puts "Finding or creating repo #{repo_nwo}..."
        repo = Seeds::Objects::Repository.create_with_nwo(
          nwo: repo_nwo,
          setup_master: true,
          is_public: true,
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
            "stacks.md" => "# Stacks!\n",
          }
        )
        if options[:needs_rebase]
          # Set up a stack that needs to be rebased.
          # First, create a properly stacked series of branches.
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: "stack-branch-1-#{branch_suffix}",
            from_branch: repo.default_branch,
            message: "Add one.txt",
            committer: user,
            files: {
              "#{branch_suffix}/one.txt" => "ONE",
            }
          )
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: "stack-branch-2-#{branch_suffix}",
            from_branch: "stack-branch-1-#{branch_suffix}",
            message: "Add two.txt",
            committer: user,
            files: {
              "#{branch_suffix}/two.txt" => "TWO",
            }
          )
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: "stack-branch-3-#{branch_suffix}",
            from_branch: "stack-branch-2-#{branch_suffix}",
            message: "Add three.txt",
            committer: user,
            files: {
              "#{branch_suffix}/three.txt" => "THREE",
            }
          )

          # Next, add a commit to each branch.
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: "stack-branch-1-#{branch_suffix}",
            message: "Update one.txt",
            committer: user,
            files: {
              "#{branch_suffix}/one.txt" => "ONE\n\n111",
            }
          )
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: "stack-branch-2-#{branch_suffix}",
            message: "Update two.txt",
            committer: user,
            files: {
              "#{branch_suffix}/two.txt" => "TWO\n\n222",
            }
          )
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: "stack-branch-3-#{branch_suffix}",
            message: "Update three.txt",
            committer: user,
            files: {
              "#{branch_suffix}/three.txt" => "THREE\n\n333",
            }
          )
        else
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: "stack-branch-1-#{branch_suffix}",
            from_branch: repo.default_branch,
            message: "The first stacked change",
            committer: user,
            files: {
              "stacks.md" => "# Stacks!\n\nStacks allow us to build up a change incrementally.\n",
            }
          )
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: "stack-branch-2-#{branch_suffix}",
            from_branch: "stack-branch-1-#{branch_suffix}",
            message: "The second stacked change",
            committer: user,
            files: {
              "stacks.md" => (
                "# Stacks!\n\nStacks allow us to build up a change incrementally.\n" +
                "Each change can be reviewed independently of the others.\n"
              ),
            }
          )
          Seeds::Objects::Commit.create(
            repo:,
            branch_name: "stack-branch-3-#{branch_suffix}",
            from_branch: "stack-branch-2-#{branch_suffix}",
            message: "The third stacked change",
            committer: user,
            files: {
              "stacks.md" => (
                "# Stacks!\n\nStacks allow us to build up a change incrementally.\n" +
                "Each change can be reviewed independently of the others, then shipped one by one or together.\n"
              ),
            }
          )
        end

        puts "Creating pull requests ..."
        pulls = [
          repo.default_branch,
          "stack-branch-1-#{branch_suffix}",
          "stack-branch-2-#{branch_suffix}",
          "stack-branch-3-#{branch_suffix}",
        ].each_cons(2).with_index.map do |(base, head), idx|
          num = idx + 1
          begin
            pull = ::PullRequest.create_for!(
              repo,
              user:,
              title: "Stack #{branch_suffix}, part #{num}",
              body: "A stacked PR (#{num} of 3)",
              base:,
              head:,
            )
          rescue => e
            puts "Error creating pull request for #{head} -> #{base}: #{e.message}"
            puts e.backtrace.join("\n")
            next
          end

          puts pull.permalink
          pull
        end

        pulls.compact!

        begin
          puts "Creating the stack ..."
          result = ::PullRequests::Stacks.create(pulls, actor: user)
          result.raise! if result.is_a?(::PullRequests::Stacks::Error)
        rescue => e
          puts "Error creating stack: #{e.message}"
          puts e.backtrace.join("\n")
        end

        puts "Done!"
      end
    end
  end
end
