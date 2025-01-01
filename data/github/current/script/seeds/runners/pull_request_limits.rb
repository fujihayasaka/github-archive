# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class PullRequestLimits < Seeds::Runner
      DEFAULT_AUTHOR = "monalisa"
      DEFAULT_ORG_NAME = "github"
      DEFAULT_ORG_REPO_NAME = "github"
      DEFAULT_REPO_NAME = "smile"
      DEFAULT_REVIEWERS = %w(collaborator).freeze

      def self.run(options = {})
        puts "Setting up users and repos..."
        # Ensure PR author exists
        author_login = options[:author] || DEFAULT_AUTHOR
        puts "\tFinding or creating PR author #{author_login}..."
        author = Seeds::Objects::User.create(login: author_login)

        # Ensure PR reviewers exist
        reviewer_logins = options[:reviewers] || DEFAULT_REVIEWERS
        reviewers = reviewer_logins.map do |reviewer_login|
          puts "\tFinding or creating PR reviewer #{reviewer_login}..."
          Seeds::Objects::User.create(login: reviewer_login)
        end
        reviewer_user_ids = reviewers.map(&:id)

        # Ensure repo exists
        nwo = options[:nwo] || "#{author_login}/#{DEFAULT_REPO_NAME}"
        puts "\tFinding or creating repo #{nwo}..."
        repo = Seeds::Objects::Repository.create_with_nwo(nwo: nwo, setup_master: true, is_public: true)

        # Ensure org exists
        org = \
          if repo.in_organization?
            repo.organization
          else
            puts "\tCreating organization #{DEFAULT_ORG_NAME}..."
            Seeds::Objects::Organization.create(login: DEFAULT_ORG_NAME, admin: author)
          end
        # Ensure org has verifiable domain
        if !org.verifiable_domains.exists?
          verifiable_domain = VerifiableDomain.normalize_domain(author.git_author_email)
          puts "\tCreating verified domain #{verifiable_domain} for org #{org.login}..."
          org.verifiable_domains.create(domain: verifiable_domain, verified: true)
        end

        # Ensure script has one user-owned repo and one org-owned repo
        if repo.in_organization?
          org_repo = repo
          # Create user-owned repo
          user_repo_nwo = "#{author_login}/#{DEFAULT_REPO_NAME}"
          puts "\tCreating user-owned repo #{user_repo_nwo}..."
          user_repo = Seeds::Objects::Repository.create_with_nwo(nwo: user_repo_nwo, setup_master: true)
        else
          user_repo = repo
          # Create org-owned repo
          org_repo_nwo = "#{org.login}/#{DEFAULT_ORG_REPO_NAME}"
          puts "\tCreating org-owned repo #{org_repo_nwo}..."
          org_repo = Seeds::Objects::Repository.create_with_nwo(nwo: org_repo_nwo, setup_master: true)
        end

        # Ensure all users have write permissions to user-owned and org-owned repos
        all_users = [author] | reviewers
        all_users.each do |user|
          puts "\tAdding #{user} to #{user_repo.nwo} as member with write permissions..."
          user_repo.add_member(user)
          puts "\tAdding #{user} to #{org_repo.nwo} as member with write permissions..."
          org.add_member(user)
          org_repo.add_member(user)
        end

        # Set options - only need these for limit cases
        total_number_of_prs = 8 # 4 limit cases per repo

        # Loop through each repo, create limit-case PRs in each
        [user_repo, org_repo].each do |repo|
          puts "\nCreating 4 limit-case pull requests in #{repo.nwo}..."

          # Limit-case PRs for file/line limits
          puts "\t\tSeeding PR: fewer than 1000 files and fewer than 6000 lines..."
          seed_lt_1000_files_lt_6000_lines_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids)
          puts "\t\tDone!\n"

          puts "\t\tSeeding PR: fewer than 1000 files and more than 6000 lines..."
          seed_lt_1000_files_gt_6000_lines_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids)
          puts "\t\tDone!\n"

          puts "\t\tSeeding PR: more than 1000 files and fewer than 6000 lines..."
          seed_gt_1000_files_lt_6000_lines_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids)
          puts "\t\tDone!\n"

          puts "\t\tSeeding PR: more than 1000 files and more than 6000 lines..."
          seed_gt_1000_files_gt_6000_lines_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids)
          puts "\t\tDone!\n"
        end

        puts "\nDone!"
      end

      def self.create_comments(issue:, number_of_comments: 1, possible_commenter_ids: [])
        number_of_comments.times do |_i|
          commenter = User.find(possible_commenter_ids.sample)
          body = Faker::Lorem.paragraph
          ::Seeds::Objects::IssueComment.create(issue: issue, user: commenter, body: body)
        end
      end

      # Limit case 1: < 1000 files  < 6000 lines
      def self.seed_lt_1000_files_lt_6000_lines_pr(repo:, author:, reviewer_user_ids:)
        base_branch_name = "lt1000-lt6000-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for lt1000/lt6000 PR",
          files: { "README.md" => "# Limit case: fewer than 1000 files and fewer than 6000 lines" }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        files_count = 500 # < 1000
        puts "\t\tCommitting #{files_count} files with 5 to 10 lines each..."
        head_ref.append_commit({ message: "Add #{files_count} files with 5 to 10 lines each", committer: author, author: author }, author) do |changes|
          files_count.times do |i|
            lines_per_file = rand(5..10) # Max 10 * 500 = 5000 < 6000
            content = (1..lines_per_file).map { |n| "Limit file #{i} line #{n}" }.join("\n")
            changes.add("limit_cases/lt1000_lt6000/file_#{i}.txt", content)
          end
        end

        puts "\t\tOpening PR (fewer than 1000 files and fewer than 6000 lines)..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "PR: fewer than 1000 files and fewer than 6000 lines",
          body: "This PR adds #{files_count} files with 5-10 lines each (maximum 5000 lines).",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
        )
      end

      # Limit case 2: < 1000 files  > 6000 lines
      def self.seed_lt_1000_files_gt_6000_lines_pr(repo:, author:, reviewer_user_ids:)
        base_branch_name = "lt1000-gt6000-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for lt1000/gt6000 PR",
          files: { "README.md" => "# Limit case: fewer than 1000 files and more than 6000 lines" }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        files_count = 600 # < 1000
        puts "\t\tCommitting #{files_count} files with 11-20 lines each..."
        head_ref.append_commit({ message: "Add #{files_count} files with 11-20 lines each", committer: author, author: author }, author) do |changes|
          files_count.times do |i|
            lines_per_file = rand(11..20) # Minimum: 600 * 11 = 6600 > 6000
            content = (1..lines_per_file).map { |n| "Limit file #{i} line #{n}" }.join("\n")
            changes.add("limit_cases/lt1000_gt6000/file_#{i}.txt", content)
          end
        end

        puts "\t\tOpening PR (fewer than 1000 files and more than 6000 lines)..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "PR: fewer than 1000 files and more than 6000 lines",
          body: "This PR adds #{files_count} files with 11-20 lines each (minimum 6600 lines).",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
        )
      end

      # Limit case 3: > 1000 files  < 6000 lines
      def self.seed_gt_1000_files_lt_6000_lines_pr(repo:, author:, reviewer_user_ids:)
        base_branch_name = "gt1000-lt6000-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for gt1000/lt6000 PR",
          files: { "README.md" => "# Limit case: more than 1000 files and fewer than 6000 lines" }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        files_count = 1101 # > 1000
        puts "\t\tCommitting #{files_count} files with 1 to 5 lines each..."
        head_ref.append_commit({ message: "Add #{files_count} files with 1 to 5 lines each", committer: author, author: author }, author) do |changes|
          files_count.times do |i|
            lines_per_file = rand(1..5)  # Max: 1101 * 5 = 5505 < 6000
            content = (1..lines_per_file).map { |n| "Limit file #{i} line #{n}" }.join("\n")
            changes.add("limit_cases/gt1000_lt6000/file_#{i}.txt", content)
          end
        end

        puts "\t\tOpening PR (more than 1000 files and fewer than 6000 lines)..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "PR: more than 1000 files and fewer than 6000 lines",
          body: "This PR adds #{files_count} files with 1 to 5 lines each (maximum 5505 lines).",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
        )
      end

      # Limit case 4: > 1000 files  > 6000 lines
      def self.seed_gt_1000_files_gt_6000_lines_pr(repo:, author:, reviewer_user_ids:)
        base_branch_name = "gt1000-gt6000-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for gt1000/gt6000 PR",
          files: { "README.md" => "# Limit case: more than 1000 files and more than 6000 lines" }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        files_count = 1101 # > 1000
        puts "\t\tCommitting #{files_count} files with 6 to 10 lines each..."
        head_ref.append_commit({ message: "Add #{files_count} files with 6 to 10 lines each", committer: author, author: author }, author) do |changes|
          files_count.times do |i|
            lines_per_file = rand(6..10) # Minimum: 1101 * 6 = 6606 > 6000
            content = (1..lines_per_file).map { |n| "Limit file #{i} line #{n}" }.join("\n")
            changes.add("limit_cases/gt1000_gt6000/file_#{i}.txt", content)
          end
        end

        puts "\t\tOpening PR (more than 1000 files and more than 6000 lines)..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "PR: more than 1000 files and more than 6000 lines",
          body: "This PR adds #{files_count} files with 6 to 10 lines each (minimum 6606 lines).",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
        )
      end
    end
  end
end
