# typed: true
# frozen_string_literal: true

require_relative "../runner"
require_relative "pull_request_limits"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class PullRequests < Seeds::Runner
      DEFAULT_AUTHOR = "monalisa"
      DEFAULT_NUM_DRAFTS = 0
      DEFAULT_NUM_COMMENTS = 1
      DEFAULT_NUM_FILES_CHANGED = 50
      DEFAULT_ORG_NAME = "github"
      DEFAULT_ORG_REPO_NAME = "github"
      DEFAULT_REPO_NAME = "smile"
      DEFAULT_REVIEWERS = %w(collaborator).freeze
      MINIMUM_NUM_COMMITS = 5

      def self.help
        <<~HELP
        Seed pull request data for local development.

        - Creates fourteen PRs (seven in user-owned repo, seven in org-owned repo):
          - One with one changed file
          - One with several changed files and review comments
          - One with a number of changed files specified by the user
          - One with a number of commits specified by the user
          - One based off of a branch of the main branch, with each branch having one changed file
          - One with a large number of files and changes to files
          - One with 1000 files, each with 20 lines of content
        - When -large_prs flag is used, creates 12 additional PRs per repo with stress testing characteristics:
          - One with 2000 diff lines spread between files
          - One with 6001 diff lines spread between files
          - One with 3000 diff lines
          - One with 1100 files
          - One with 275 files changed and 50 review threads
          - One with 50 review threads
          - One with multiple file types (.js, .cpp, .sh, .css, .go, .java, .rb, .py, .xml, .yaml, .txt, .mdx)
          - One MASSIVE PR with 500 files across 20 languages, 10k-12k LOC changes, 50 comments
          - Four limit-case PRs for file/line limits:
            - < 1000 files and < 6000 lines
            - < 1000 files and > 6000 lines
            - > 1000 files and < 6000 lines
            - > 1000 files and > 6000 lines
        - Ensures given PR author exists
        - Ensures given PR reviewers exist
        - Ensures given repo exists

        Options:
          -author, -u
            String name of the pull request author.
            Defaults to #{DEFAULT_AUTHOR}.
            Example: bin/seed pull_requests -u octocat
          -num_drafts, -d
            Integer number of draft PRs to create.
            Defaults to #{DEFAULT_NUM_DRAFTS}. Maximum 10.
            Example: bin/seed pull_requests -d 5
          -num_comments, -c
            Integer number of issue comments in the PR.
            Defaults to #{DEFAULT_NUM_COMMENTS}.
            Example: bin/seed pull_requests -c 5
          -num_commits, -m
            Integer number of commits in the PR.
            Defaults to #{Seeds::Objects::Commit::DEFAULT_NUM_RANDOM_COMMITS}. Minimum #{MINIMUM_NUM_COMMITS}.
            Example: bin/seed pull_requests -c 50
          -num_files_changed, -n
            Integer number of files changed in the PR.
            Defaults to #{DEFAULT_NUM_FILES_CHANGED}.
            Example: bin/seed pull_requests -n 25
          -nwo, -r
            String "name with owner" of the pull request base repository.
            Defaults to #{DEFAULT_AUTHOR}/#{DEFAULT_REPO_NAME}.
            Example: bin/seed pull_requests -r octocat/octorepo
          -reviewers, -v
            Array of reviewer logins.
            Defaults to #{DEFAULT_REVIEWERS}.
            Example: bin/seed pull_requests -v reviewer1 reviewer2
          -large_prs, -l
            Boolean flag to create additional large PRs for stress testing.
            Defaults to false. When enabled, creates 11 additional PRs with various characteristics,
            including 4 limit-case PRs for file/line limits.
            Example: bin/seed pull_requests -l
          -comment_outside_the_diff, -cotd
            Boolean flag to create a pull request with comments outside the diff.
            Defaults to false. When enabled, creates a PR with comments outside the diff.
            Example: bin/seed pull_requests -cotd
          -pull_request_groups, -g
            Boolean flag to create a pull request with several diff hunks.
            Defaults to false. When enabled, creates a PR with several diff hunks.
            Example: bin/seed pull_requests -g
        HELP
      end

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

        # Set options
        create_large_prs = options[:large_prs] || false
        total_number_of_prs = create_large_prs ? 38 : 14  # 14 regular + 24 large (15 stress + 8 limit-case + 1 massive)
        number_of_draft_prs = options[:num_drafts] || DEFAULT_NUM_DRAFTS
        # Create array of booleans we can pass one-by-one into PR create :draft option
        draft_prs = Array.new(total_number_of_prs) { |i| i < number_of_draft_prs }.shuffle
        given_number_of_commits = total_number_of_commits = (options[:num_commits] || Seeds::Objects::Commit::DEFAULT_NUM_RANDOM_COMMITS)
        number_of_comments = options[:num_comments] || DEFAULT_NUM_COMMENTS
        comment_outside_the_diff = options[:comment_outside_the_diff] || false
        num_files_changed = options[:num_files_changed] || DEFAULT_NUM_FILES_CHANGED
        create_pr_for_groups = options[:pull_request_groups] || false

        # Loop through each repo, create PRs in each
        [user_repo, org_repo].each do |repo|
          prs_per_repo = create_large_prs ? 19 : 7  # 7 regular + 8 stress + 4 limit-case when large_prs enabled
          puts "\nCreating #{prs_per_repo} pull requests in #{repo.nwo}..."
          possible_commenter_ids = repo.members.ids

          puts "\tAdding initial files to repo...\n"
          base_commit = \
            Seeds::Objects::Commit.create(
              repo: repo,
              committer: author,
              message: "Initial commit",
              files: {
                "CODEOWNERS" => "*.rb @#{author.login} @octocat2",
                "groups/calculator.rb" => initial_calculator_file_contents,
                "one/two/update_me.rb" => "todo: update me",
                "one/two/three/delete_me.md" => "todo: delete me",
                "rename_me.txt" => "todo: rename me"
              }
            )

          # PR with one changed file
          puts "\tCreating pull request with one changed file..."
          simple_pr_ref_name = "branch-#{SecureRandom.hex}"
          puts "\t\tCommitting changes to new branch #{simple_pr_ref_name}..."
          Seeds::Objects::Commit.create(
            repo: repo,
            message: "Changing one file",
            committer: author,
            branch_name: simple_pr_ref_name,
            files: {
              "File.md" => "Last updated #{Time.current}"
            }
          )
          puts "\t\tOpening PR..."
          simple_pull = ::PullRequest.create_for!(
            repo,
            user: author,
            title: "Pull request with 1 changed file",
            body: "This pull request has one changed file.",
            head: simple_pr_ref_name,
            base: repo.default_branch,
            reviewer_user_ids: reviewer_user_ids,
            draft: draft_prs.shift,
          )
          puts "\t\tAdding comments..."
          create_comments(issue: simple_pull.issue, number_of_comments:, possible_commenter_ids:)
          puts "\t\tDone!\n"

          # PR with several changed files
          puts "\tCreating pull request with several changed files..."
          complex_pr_ref_name = "branch-#{SecureRandom.hex}"
          complex_pr_head_ref = repo.refs.create("refs/heads/#{complex_pr_ref_name}", base_commit.oid, author)
          complex_pr_metadata = { message: "Changing several files", committer: author, author: author }
          puts "\t\tCommitting changes to new branch #{complex_pr_ref_name}..."
          complex_pr_head_ref.append_commit(complex_pr_metadata, author) do |changes|
            changes.add("Gemfile.lock", "# manifest file")
            changes.add("File.md", "file\nfile\nfile")
            changes.add("file_with_a_pretty_pretty_pretty_pretty_long_name", "Name should be truncated")
            changes.add("one/two/viewed.rb", "todo: mark me as viewed")
            changes.add("one/two/update_me.rb", "Updated!")
            changes.add("Gopkg.lock", "hidden generated file")
            changes.move("rename_me.txt", "renamed.txt", "todo: rename me")
            changes.remove("one/two/three/delete_me.md")
            changes.add("very_large.txt", "a\n" * 10_000)
            changes.add("rails.svg", File.read(Rails.root.join("test/fixtures/files/rails.svg")))
          end

          puts "\t\tOpening PR..."
          complex_pull = ::PullRequest.create_for!(
            repo,
            user: author,
            title: "Pull request with several changed files and reviews",
            body: "This pull request has several changed files.",
            head: complex_pr_head_ref.name,
            base: repo.default_branch,
            reviewer_user_ids: reviewer_user_ids,
            draft: draft_prs.shift,
          )
          puts "\t\tAdding comments..."
          # create pull request level comments
          create_comments(issue: complex_pull.issue, number_of_comments:, possible_commenter_ids:)

          # create diff level comments, some with suggested changes
          create_pull_request_review_thread(pull: complex_pull, possible_commenter_ids:, position_options: { path: "Gemfile.lock", side: :right, line: 1 })
          create_pull_request_review_thread(pull: complex_pull, possible_commenter_ids:, position_options: { path: "very_large.txt", side: :right, line: 5000 })
          create_pull_request_review_thread(pull: complex_pull, possible_commenter_ids:, position_options: { path: "very_large.txt", side: :right, line: 5002 }, with_suggested_change: true)
          create_pull_request_review_thread(pull: complex_pull, possible_commenter_ids:, position_options: { path: "File.md", side: :right, line: 2 }, with_suggested_change: true)

          # creating multiple threads on the same line
          create_pull_request_review_thread(pull: complex_pull, possible_commenter_ids:, position_options: { path: "one/two/update_me.rb", side: :left, line: 1 })
          create_pull_request_review_thread(pull: complex_pull, possible_commenter_ids:, position_options: { path: "one/two/update_me.rb", side: :left, line: 1 }, with_suggested_change: true)

          puts "\t\tMarking file as viewed..."
          UserReviewedFile.create(
            filepath: "one/two/viewed.rb",
            user: author,
            pull_request: complex_pull,
            head_sha: complex_pull.head_sha,
          )
          puts "\t\tDone!\n"

          # PR with a number of changed files
          puts "\tCreating pull request with #{num_files_changed} changed files..."
          large_pr_ref_name = "branch-#{SecureRandom.hex}"
          large_pr_head_ref = repo.refs.create("refs/heads/#{large_pr_ref_name}", base_commit.oid, author)
          large_pr_metadata = { message: "Changing a number of files", committer: author, author: author }
          puts "\t\tCommitting changes to new branch #{large_pr_ref_name}..."
          large_pr_head_ref.append_commit(large_pr_metadata, author) do |changes|
            num_files_changed.times do |i|
              changes.add("one/two/file-#{i}.txt", "File #{i}")
            end
            changes.add("one/two/update_me.rb", "Update existing file")
          end

          puts "\t\tOpening PR..."
          large_pull = ::PullRequest.create_for!(
            repo,
            user: author,
            title: "Pull request with #{num_files_changed} changed files",
            body: "This pull request has #{num_files_changed} changed files.",
            head: large_pr_head_ref.name,
            base: repo.default_branch,
            reviewer_user_ids: reviewer_user_ids,
            draft: draft_prs.shift,
          )
          puts "\t\tAdding comments..."
          create_comments(issue: large_pull.issue, number_of_comments:, possible_commenter_ids:)
          create_pull_request_review_thread(pull: large_pull, possible_commenter_ids:, position_options: { path: "one/two/file-1.txt", side: :right, line: 1 })
          puts "\t\tDone!\n"

          # PR with many commits
          puts "\tCreating pull request with #{total_number_of_commits} commits..."
          if given_number_of_commits < MINIMUM_NUM_COMMITS
            total_number_of_commits = MINIMUM_NUM_COMMITS
            puts "\tUnable to create only #{given_number_of_commits} commits. Minimum is #{MINIMUM_NUM_COMMITS}"
          end

          commits_pr_ref_name = "branch-with-#{total_number_of_commits}-commits-#{SecureRandom.hex}"
          past_date = (Time.now - 1.day).iso8601

          puts "\t\tCommitting changes to new branch #{commits_pr_ref_name}..."
          # Commit with link in message
          url = Faker::Internet.url
          Seeds::Objects::Commit.create(
            branch_name: commits_pr_ref_name,
            committer: author,
            date: past_date,
            files: { "banlist-#{SecureRandom.hex}" => url },
            message: "Add #{url} to banlist",
            repo: repo,
          )

          # Commit with multiple authors
          coauthor = reviewers.sample
          Seeds::Objects::Commit.create(
            branch_name: commits_pr_ref_name,
            committer: author,
            date: past_date,
            files: { "foo-#{SecureRandom.hex}" => "foo" },
            message: "Pair programmed :raised_hands:\n\nCo-authored-by: #{coauthor.login} <#{coauthor.git_author_email}>",
            repo: repo,
          )

          # Verified commit (using web flow)
          # Requires web flow setup to be in place, which is true by default when
          # developing in a gh/gh codespace
          author.set_commit_verification_status_state(actor: author, state: "enabled")
          head_ref = repo.heads.find(commits_pr_ref_name)
          metadata = {
            committer: {
              name: GitHub.web_committer_name,
              email: GitHub.web_committer_email,
            },
            author: {
              name: author.git_author_name,
              email: author.git_author_email,
            },
            authored_date: past_date,
            committed_date: past_date,
            message: "Committing changes via the GitHub web interface at #{past_date}"
          }
          head_ref.append_commit(metadata, author, { sign: true }) do |changes|
            changes.add("verified-#{SecureRandom.hex}", "Committed via web flow at #{past_date}")
          end

          # Create commit on behalf of org (org-owned repo only)
          if repo.in_organization?
            # Commit must be signed, so we'll use same metadata as above, but change the message
            verifiable_domain = org.verifiable_domains.first.domain
            metadata[:message] = "V important business\n\non-behalf-of: #{org.login} <org@#{verifiable_domain}>"
            head_ref.append_commit(metadata, author, { sign: true }) do |changes|
              changes.add("on-behalf-of-#{SecureRandom.hex}", "Committed on behalf of #{org} via web flow at #{past_date}")
            end
          end

          number_of_commits_created_so_far = repo.in_organization? ? 4 : 3

          # Create more commits if necessary
          number_of_random_commits = total_number_of_commits - number_of_commits_created_so_far
          if number_of_random_commits > 0
            Seeds::Objects::Commit.random_create(
              repo: repo,
              count: number_of_random_commits,
              branch: commits_pr_ref_name
            )
          end

          puts "\t\tOpening PR..."
          commits_pull = ::PullRequest.create_for!(
            repo,
            user: author,
            title: "Pull request with #{total_number_of_commits} commits",
            body: "This pull request has #{total_number_of_commits} commits.",
            head: commits_pr_ref_name,
            base: repo.default_branch,
            reviewer_user_ids: reviewer_user_ids,
            draft: draft_prs.shift,
          )
          puts "\t\tDone!\n"

          puts "\t\tSeeding pull request with a large number of files and changes to files..."
          seed_large_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
          puts "\t\tDone!\n"

          puts "\t\tSeeding pull request with 1000 files, each with 20 lines of content..."
          seed_thousand_file_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
          puts "\t\tDone!\n"

          if create_large_prs
            puts "\t\tSeeding pull request with 2000 diff lines..."
            seed_2000_diff_lines_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding pull request with 6001 diff lines..."
            seed_6001_diff_lines_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding custom PR: 1 small change + 1 single-file deletion of 6000 lines..."
            seed_pr_single_deletion_6000(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding custom PR: 1 small change + deletion of 6000 lines spread over 4 diffs..."
            seed_pr_deletion_6000_over_4_diffs(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding pull request with 275 files and 50 comments..."
            seed_275_files_45_comments_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, possible_commenter_ids: possible_commenter_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding pull request with 5000 line diff..."
            seed_pr_huge_5000_and_small_5(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding pull request with multiple file types..."
            seed_multiple_file_types_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding pull request with 500 files across 20 languages, 80+ threads, 200+ comments..."
            seed_multilanguage_p95_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, possible_commenter_ids: possible_commenter_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"
          end

          if comment_outside_the_diff
            puts "\t\tSeeding pull request with comments outside the diff..."
            seed_comments_outside_the_diff_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, possible_commenter_ids: possible_commenter_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"
          end

          if create_pr_for_groups
            puts "\tCreating PR with several diff hunks..."
            seed_pr_with_several_diff_hunks(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
          end

          puts "\tCreating pull request branch off of a branch..."
          # Create the non-main base branch
          branch_off_branch_base_ref_name = "initial-based-off-branch-for-test"
          puts "\t\tCommitting changes to base branch #{branch_off_branch_base_ref_name}..."
          Seeds::Objects::Commit.create(
            repo: repo,
            message: "Changing one file",
            committer: author,
            branch_name: branch_off_branch_base_ref_name,
            from_branch: repo.default_branch,
            files: {
              "file-1.md" => "Last updated #{Time.current}"
            }
          )

          # Create the new head branch
          branch_off_branch_head_ref_name = "branched-off-base-branch-for-test"
          puts "\t\tCommitting changes to head branch #{branch_off_branch_head_ref_name}..."
          Seeds::Objects::Commit.create(
            repo: repo,
            message: "Changing one file",
            committer: author,
            branch_name: branch_off_branch_head_ref_name,
            from_branch: branch_off_branch_base_ref_name,
            files: {
              "file-2.md" => "Last updated #{Time.current}"
            }
          )

          puts "\t\tOpening PR..."
          branch_off_branch_pull = ::PullRequest.create_for(
            repo,
            user: author,
            title: "Pull request branched off of a branch",
            body: "This pull request is not pointed at main",
            head: branch_off_branch_head_ref_name,
            base: branch_off_branch_base_ref_name,
            reviewer_user_ids: reviewer_user_ids,
            draft: draft_prs.shift,
          )
          puts "\t\tDone!\n"
        end

        # Add limit-case PRs when large_prs is enabled
        if create_large_prs
          puts "\tCreating limit-case pull requests..."
          PullRequestLimits.execute(options)
        end
      end

      def self.create_comments(issue:, number_of_comments: 1, possible_commenter_ids: [])
        number_of_comments.times do |_i|
          commenter = User.find(possible_commenter_ids.sample)
          body = Faker::Lorem.paragraph
          ::Seeds::Objects::IssueComment.create(issue: issue, user: commenter, body: body)
        end
      end

      def self.create_pull_request_review_thread(pull:, possible_commenter_ids: [], position_options: {}, with_suggested_change: false)
        # Creates a pull request review containing a thread and comment
        user = User.find(possible_commenter_ids.sample)
        review = pull.pending_review_for(user: user, head_sha: pull.head_sha)
        thread = review.build_thread

        start_line = position_options.fetch(:start_line, nil)
        start_side = position_options.fetch(:start_side, nil)
        side       = position_options.fetch(:side)
        line       = position_options.fetch(:line)
        path       = position_options.fetch(:path)

        body = Faker::Lorem.paragraph
        if with_suggested_change
          body += "\n```suggestion\n#{Faker::Lorem.sentence}\n```"
        end

        comment = thread.build_first_comment(
          body: body,
          path: path,
          diff: pull.historical_comparison.diffs,
          start_line: start_line,
          start_side: start_side,
          line: line,
          side: side,
        )
        comment.save!
        review.save!
        review.trigger(:comment)
      end

      def self.create_pull_request_review_thread_outside_of_diff(pull:, comparison:, possible_commenter_ids: [], positioning: {})
        user = User.find(possible_commenter_ids.sample)
        review = pull.pending_review_for(user: user, head_sha: pull.head_sha)

        ::PullRequests::ReviewComments::Create.create_from_parameters(
          pull_request: pull,
          review:,
          review_event: :comment,
          body: Faker::Lorem.paragraph,
          actor: user,
          destination_base_commit_oid: comparison.start_commit.oid,
          destination_head_commit_oid: comparison.end_commit.oid,
          parameters: {
            # New positional format - packages/pull_requests/app/lib/pull_requests/comment_position/positions.rb
            positioning: positioning,
          }.compact
        )
      end

      def self.create_pull_request_groups(pull:)
        hunks = ::PullRequests::Copilot::DiffHunk.diffs_to_hunks(pull.diffs.entries)
        change_groups = hunks.map.with_index do |hunk, i|
          group = ::PullRequests::ChangeGroup.new(
           actor: pull.user,
           pull_request: pull,
           repository: pull.repository,
           name: Faker::Quote.yoda.slice(0, 48),
           base_commit_oid: pull.base_sha,
           head_commit_oid: pull.head_sha,
           priority: 10 - i,
           bug_risk: 0,
           confidence: 0,
         )
          group.add_hunk_position(hunk)
          group
        end
        change_groups.each(&:save!)
      end

      def self.seed_large_pr(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "large-pr-branch-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        # Create a large number of files in the base branch (branched from main)
        base_commit = \
            Seeds::Objects::Commit.create(
            repo: repo,
            committer: author,
            branch_name: base_branch_name,
            from_branch: repo.default_branch,
            message: "Initial commit with many files",
            files: {
              "README.md" => "# Project Documentation\n\nThis is a sample project.",
              ".gitignore" => "/tmp\n/log\n/node_modules\n.DS_Store"
            }.merge(
              # Add 50 more files to have enough to modify
              (1..50).map { |i| ["files/to_be_modified_#{i}.txt", "Original content #{i}"] }.to_h
            )
            )

        puts "\t\tCreating head branch #{head_branch_name}..."

        # Create a large number of files in the head branch (branched from base)
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting large changes to head branch #{head_branch_name}..."
        head_ref.append_commit({ message: "Changing a number of files", committer: author, author: author }, author) do |changes|
          # Add new files
          50.times do |i|
            changes.add("one/two/new_file_#{i}.txt", "New file #{i}\n" +
            "This is additional content for file #{i}.\n" +
            "Created at: #{Time.now.iso8601}\n" +
            "Random ID: #{SecureRandom.uuid}\n" +
            "Content: #{Faker::Lorem.paragraph(sentence_count: 5)}")
          end

          # Modify existing files
          25.times do |i|
            changes.add("files/to_be_modified_#{i}.txt", "Modified content #{i}\n" +
            "This file has been significantly modified with additional content.\n" +
            "Multiple paragraphs of text have been added to increase the diff size.\n" +
            "Line 1: #{SecureRandom.hex(50)}\n" +
            "Line 2: #{SecureRandom.hex(50)}\n" +
            "Line 3: #{SecureRandom.hex(50)}\n" +
            "Line 4: #{Faker::Lorem.paragraphs(number: 3).join("\n\n")}\n" +
            "Line 5: #{Time.now.iso8601}\n" +
            "#{Faker::Lorem.paragraphs(number: 100).join("\n\n")}\n")
          end

          # Remove some files
          15.times do |i|
            changes.remove("files/to_be_modified_#{i + 30}.txt")
          end
        end

        puts "\t\tOpening PR..."

        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Very large pull request with many files and changes",
          body: "Very large pull request with many files and changes",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      def self.seed_thousand_file_pr(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "thousand-files-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        # Start with a minimal base branch
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for 1000-file PR",
          files: {
            "README.md" => "# 1000 File PR\n\nThis is a test base for a huge PR."
          }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting 1000 new files to head branch #{head_branch_name}..."
        head_ref.append_commit({ message: "Add 1000 files", committer: author, author: author }, author) do |changes|
          1000.times do |i|
            content = (1..20).map { |n| "Line #{n} of file #{i}" }.join("\n")
            changes.add("large_folder/file_#{i}.txt", content)
          end
        end

        puts "\t\tOpening PR for 1000 files..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with 1000 changed files",
          body: "This pull request has 1000 changed files.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      def self.seed_2000_diff_lines_pr(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "2000-diff-lines-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        # Create base with substantial initial content to provide context for diffs
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for 2000 diff lines PR",
          files: {
            "README.md" => "# 2000 Diff Lines PR\n\nBase content for large diff.\n\n## Features\n\n- Feature A\n- Feature B\n- Feature C\n\n## Installation\n\nRun the following commands...",
            "src/main.rb" => (1..150).map { |n| "# Line #{n}: Original implementation\ndef method_#{n}\n  puts 'original method #{n}'\nend\n" }.join("\n"),
            "src/utils.rb" => (1..100).map { |n| "# Utility function #{n}\ndef util_#{n}(param)\n  # Original logic for util #{n}\n  return param * #{n}\nend\n" }.join("\n"),
            "config/settings.yml" => (1..50).map { |n| "setting_#{n}: original_value_#{n}" }.join("\n"),
            "docs/guide.md" => (1..80).map { |n| "## Section #{n}\n\nOriginal documentation for section #{n}.\nThis explains how to use feature #{n}.\n" }.join("\n"),
            "lib/processor.rb" => (1..120).map { |n| "class Processor#{n}\n  def process\n    # Original processing logic #{n}\n    puts 'processing #{n}'\n  end\nend\n" }.join("\n")
          }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting changes to create ~2000 diff lines with context..."
        head_ref.append_commit({ message: "Update ~2000 lines with context", committer: author, author: author }, author) do |changes|
          # Modify existing files to create diffs with context lines
          changes.add("README.md", "# 2000 Diff Lines PR\n\nUpdated content for large diff demonstration.\n\n## Features\n\n- Feature A (enhanced)\n- Feature B (improved)\n- Feature C (refactored)\n- Feature D (new)\n\n## Installation\n\nRun the following updated commands...\n\n## Configuration\n\nNew configuration section.")

          # Modify main.rb with substantial changes
          updated_main = (1..150).map do |n|
            if n % 3 == 0
              "# Line #{n}: Updated implementation with new logic\ndef method_#{n}(param = nil)\n  puts 'enhanced method #{n} with param: ' + param.to_s\n  return param.nil? ? 'default' : param\nend\n"
            else
              "# Line #{n}: Original implementation\ndef method_#{n}\n  puts 'original method #{n}'\nend\n"
            end
          end.join("\n")
          changes.add("src/main.rb", updated_main)

          # Modify utils.rb with context
          updated_utils = (1..100).map do |n|
            if n % 2 == 0
              "# Utility function #{n} - UPDATED\ndef util_#{n}(param, options = {})\n  # Enhanced logic for util #{n}\n  result = param * #{n}\n  result += options[:bonus] if options[:bonus]\n  return result\nend\n"
            else
              "# Utility function #{n}\ndef util_#{n}(param)\n  # Original logic for util #{n}\n  return param * #{n}\nend\n"
            end
          end.join("\n")
          changes.add("src/utils.rb", updated_utils)

          # Update config with mixed changes
          updated_config = (1..50).map do |n|
            if n % 4 == 0
              "setting_#{n}: updated_value_#{n}_enhanced"
            else
              "setting_#{n}: original_value_#{n}"
            end
          end.join("\n") + "\n# New configuration section\nnew_setting_1: value1\nnew_setting_2: value2"
          changes.add("config/settings.yml", updated_config)

          # Update documentation with context
          updated_docs = (1..80).map do |n|
            if n % 3 == 1
              "## Section #{n} (Updated)\n\nRevised documentation for section #{n}.\nThis explains the enhanced features of #{n}.\nNew examples and use cases included.\n"
            else
              "## Section #{n}\n\nOriginal documentation for section #{n}.\nThis explains how to use feature #{n}.\n"
            end
          end.join("\n")
          changes.add("docs/guide.md", updated_docs)

          # Update processor with mixed old/new content
          updated_processor = (1..120).map do |n|
            if n % 5 == 0
              "class Processor#{n}\n  def process(data = nil)\n    # Enhanced processing logic #{n}\n    puts 'enhanced processing #{n} with data: data'\n    return process_data(data) if data\n  end\n\n  private\n\n  def process_data(data)\n    # New helper method\n    data.transform\n  end\nend\n"
            else
              "class Processor#{n}\n  def process\n    # Original processing logic #{n}\n    puts 'processing #{n}'\n  end\nend\n"
            end
          end.join("\n")
          changes.add("lib/processor.rb", updated_processor)

          # Add some new files that relate to existing content
          changes.add("src/main_helper.rb", "# Helper for main.rb\nmodule MainHelper\n  def self.format_output(method_name)\n    \"Formatted: \#{method_name}\"\n  end\nend")
          changes.add("test/main_test.rb", "require 'test_helper'\nrequire_relative '../src/main'\n\nclass MainTest < Test::Unit::TestCase\n  def test_method_1\n    assert_equal 'original method 1', method_1\n  end\nend")
        end

        puts "\t\tOpening PR with ~2000 diff lines with context..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with ~2000 diff lines (with context)",
          body: "This pull request has approximately 2000 diff lines with proper context lines showing both original and modified content.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      def self.seed_6001_diff_lines_pr(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "6001-diff-lines-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        # Create base with extensive initial content to provide context for massive diffs
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for 6001 diff lines PR",
          files: {
            "README.md" => "# 6001 Diff Lines PR\n\nBase content for massive diff.\n\n#{(1..50).map { |n| "## Section #{n}\n\nOriginal content for section #{n}." }.join("\n")}",
            "src/large_module.rb" => (1..500).map { |n| "# Module method #{n}\ndef module_method_#{n}(args)\n  # Original implementation #{n}\n  puts 'executing method #{n}'\n  return args[:value] || 'default'\nend\n" }.join("\n"),
            "lib/core_library.rb" => (1..400).map { |n| "class CoreClass#{n}\n  attr_accessor :value_#{n}\n\n  def initialize\n    @value_#{n} = 'original_#{n}'\n  end\n\n  def process\n    puts \"Processing \#{@value_#{n}}\"\n  end\nend\n" }.join("\n"),
            "config/application.yml" => (1..200).map { |n| "app_setting_#{n}:\n  enabled: true\n  value: original_value_#{n}\n  timeout: #{n * 10}" }.join("\n"),
            "docs/api_reference.md" => (1..300).map { |n| "### API Method #{n}\n\nOriginal documentation for API method #{n}.\n\n**Parameters:**\n- param1: Original description\n- param2: Original description\n\n**Returns:** Original return description\n\n**Example:**\n```ruby\nresult = api_method_#{n}(param1, param2)\n```\n" }.join("\n"),
            "test/integration_test.rb" => (1..250).map { |n| "def test_integration_#{n}\n  # Original test #{n}\n  setup_test_#{n}\n  result = run_integration_#{n}\n  assert_equal 'expected_#{n}', result\nend\n" }.join("\n"),
            "views/templates.html" => (1..150).map { |n| "<div class=\"template-#{n}\">\n  <h2>Original Template #{n}</h2>\n  <p>Original content for template #{n}</p>\n  <span class=\"status\">active</span>\n</div>" }.join("\n"),
            "assets/styles.css" => (1..100).map { |n| ".style-#{n} {\n  color: #000#{n.to_s.rjust(3, '0')};\n  background: white;\n  margin: #{n}px;\n  padding: #{n / 2}px;\n}" }.join("\n")
          }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting changes to create 6001+ diff lines with extensive context..."
        head_ref.append_commit({ message: "Massive update with 6001+ diff lines and context", committer: author, author: author }, author) do |changes|
          # Update README with major changes
          updated_readme = "# 6001 Diff Lines PR\n\nCompletely rewritten content for massive diff demonstration.\n\n#{(1..50).map do |n|
            if n % 2 == 0
              "## Section #{n} (REWRITTEN)\n\nCompletely new content for section #{n} with enhanced features and detailed explanations."
            else
              "## Section #{n}\n\nOriginal content for section #{n}."
            end
          end.join("\n")}\n\n## New Sections\n\n#{(51..80).map { |n| "## New Section #{n}\n\nBrand new content added in this update." }.join("\n")}"
          changes.add("README.md", updated_readme)

          # Massively update large_module.rb
          updated_large_module = (1..500).map do |n|
            if n % 3 == 0
              "# Module method #{n} - COMPLETELY REWRITTEN\ndef module_method_#{n}(args, options = {}, &block)\n  # Revolutionary new implementation #{n}\n  puts 'executing enhanced method #{n} with options'\n  result = args[:value] || options[:default] || 'fallback'\n  yield(result) if block_given?\n  return transform_result(result, options)\nend\n\ndef transform_result(result, options)\n  # New helper method for #{n}\n  return result.upcase if options[:uppercase]\n  result\nend\n"
            else
              "# Module method #{n}\ndef module_method_#{n}(args)\n  # Original implementation #{n}\n  puts 'executing method #{n}'\n  return args[:value] || 'default'\nend\n"
            end
          end.join("\n")
          changes.add("src/large_module.rb", updated_large_module)

          # Major updates to core_library.rb
          updated_core_library = (1..400).map do |n|
            if n % 4 == 0
              "class CoreClass#{n}\n  attr_accessor :value_#{n}, :enhanced_value_#{n}\n  attr_reader :metadata_#{n}\n\n  def initialize(options = {})\n    @value_#{n} = options[:value] || 'enhanced_#{n}'\n    @enhanced_value_#{n} = options[:enhanced] || 'super_enhanced_#{n}'\n    @metadata_#{n} = { created_at: Time.now, version: '2.0' }\n  end\n\n  def process(mode = :standard)\n    case mode\n    when :enhanced\n      puts \"Enhanced processing \#{@enhanced_value_#{n}}\"\n      return process_enhanced\n    else\n      puts \"Processing \#{@value_#{n}}\"\n    end\n  end\n\n  private\n\n  def process_enhanced\n    \"Enhanced result for \#{@enhanced_value_#{n}}\"\n  end\nend\n"
            else
              "class CoreClass#{n}\n  attr_accessor :value_#{n}\n\n  def initialize\n    @value_#{n} = 'original_#{n}'\n  end\n\n  def process\n    puts \"Processing \#{@value_#{n}}\"\n  end\nend\n"
            end
          end.join("\n")
          changes.add("lib/core_library.rb", updated_core_library)

          # Extensive config updates
          updated_config = "#{(1..200).map do |n|
            if n % 5 == 0
              "app_setting_#{n}:\n  enabled: true\n  value: completely_new_value_#{n}\n  timeout: #{n * 20}\n  features:\n    - enhanced_feature_a\n    - enhanced_feature_b\n  metadata:\n    updated_at: 2025-01-31\n    version: 2.0"
            else
              "app_setting_#{n}:\n  enabled: true\n  value: original_value_#{n}\n  timeout: #{n * 10}"
            end
          end.join("\n")}\n\n# New configuration section\nglobal_settings:\n  debug: true\n  log_level: info\n  features:\n    - new_feature_1\n    - new_feature_2"
          changes.add("config/application.yml", updated_config)

          # Major API documentation rewrite
          updated_api_docs = (1..300).map do |n|
            if n % 3 == 1
              "### API Method #{n} (UPDATED)\n\nCompletely rewritten documentation for API method #{n}.\n\n**Parameters:**\n- param1: Enhanced description with examples\n- param2: Enhanced description with validation rules\n- param3: New optional parameter\n- options: Hash of additional options\n\n**Returns:** Enhanced return description with type information\n\n**Example:**\n```ruby\n# Basic usage\nresult = api_method_#{n}(param1, param2)\n\n# Advanced usage with options\nresult = api_method_#{n}(param1, param2, param3, { timeout: 30, retries: 3 })\n```\n\n**Error Handling:**\n- Raises CustomError if param1 is invalid\n- Returns nil if param2 is missing\n"
            else
              "### API Method #{n}\n\nOriginal documentation for API method #{n}.\n\n**Parameters:**\n- param1: Original description\n- param2: Original description\n\n**Returns:** Original return description\n\n**Example:**\n```ruby\nresult = api_method_#{n}(param1, param2)\n```\n"
            end
          end.join("\n")
          changes.add("docs/api_reference.md", updated_api_docs)

          # Add substantial new content to create more diff lines
          changes.add("src/new_feature.rb", (1..300).map { |n| "class NewFeature#{n}\n  def initialize(config)\n    @config = config\n  end\n\n  def execute\n    puts \"Executing new feature #{n}\"\n  end\nend" }.join("\n"))

          changes.add("lib/extensions.rb", (1..200).map { |n| "module Extension#{n}\n  def self.included(base)\n    base.extend(ClassMethods)\n  end\n\n  module ClassMethods\n    def extended_method_#{n}\n      'extended functionality #{n}'\n    end\n  end\nend" }.join("\n"))
        end

        puts "\t\tOpening PR with 6001+ diff lines with context..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with 6001+ diff lines (with context)",
          body: "This pull request has more than 6001 diff lines with extensive context showing both original and modified content across multiple large files.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      def self.seed_3000_diff_lines_pr(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "3000-diff-lines-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for 3000 diff lines PR",
          files: {
            "README.md" => "# 3000 Diff Lines PR\n\nBase content.",
            "base_file.txt" => (1..200).map { |n| "Base line #{n}" }.join("\n")
          }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting changes to create exactly 3000 diff lines..."
        head_ref.append_commit({ message: "Create 3000 diff lines", committer: author, author: author }, author) do |changes|
          # Add files totaling 3000 lines
          6.times do |i|
            content = (1..500).map { |n| "File #{i} line #{n}" }.join("\n")
            changes.add("diff_files/file_#{i}.txt", content)
          end
        end

        puts "\t\tOpening PR with 3000 diff lines..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with 3000 diff lines",
          body: "This pull request has exactly 3000 diff lines.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      def self.seed_1100_files_pr(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "1100-files-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for 1100 files PR",
          files: {
            "README.md" => "# 1100 Files PR\n\nBase for massive file count.",
            "existing_file.txt" => "Content to be modified"
          }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting 1100 files..."
        head_ref.append_commit({ message: "Add 1100 files", committer: author, author: author }, author) do |changes|
          # Add 1099 new files
          1099.times do |i|
            changes.add("files_#{i / 100}/file_#{i}.txt", "Content for file #{i}")
          end
          # Modify the existing file to make it 1100 total changes
          changes.add("existing_file.txt", "Modified content")
        end

        puts "\t\tOpening PR with 1100 files..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with 1100 files",
          body: "This pull request changes 1100 files.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      def self.seed_275_files_45_comments_pr(repo:, author:, reviewer_user_ids:, possible_commenter_ids:, draft: false)
        base_branch_name = "275-files-45-comments-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        # Create some files to modify
        base_files = {}
        25.times do |i|
          base_files["to_modify/file_#{i}.txt"] = "Original content #{i}"
        end
        base_files["README.md"] = "# 275 Files 50 comments PR"

        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for 275 files 50 comments PR",
          files: base_files
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting 275 file changes..."
        head_ref.append_commit({ message: "Change 275 files", committer: author, author: author }, author) do |changes|
          # Add 200 new files
          200.times do |i|
            changes.add("new_files/file_#{i}.txt", "New content #{i}")
          end

          # Modify 25 existing files
          25.times do |i|
            changes.add("to_modify/file_#{i}.txt", "Modified content #{i}")
          end

          # Remove some files and add new ones to reach exactly 275
          50.times do |i|
            changes.add("additional/file_#{i}.txt", "Additional content #{i}")
          end
        end

        puts "\t\tOpening PR..."
        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with 275 files and 50 comments",
          body: "This pull request changes 275 files and will have 50 comments.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )

        puts "\t\tAdding 50 comments..."
        # Create review threads across all files and lines
        50.times do |file_index|
          create_pull_request_review_thread(
            pull: pull,
            possible_commenter_ids: possible_commenter_ids,
            position_options: {
              path: "additional/file_#{file_index}.txt",
              side: :right,
              line: 1
            }
          )
        end
      end

      def self.seed_50_review_threads_pr(repo:, author:, reviewer_user_ids:, possible_commenter_ids:, draft: false)
        base_branch_name = "50-threads-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for 50 review threads PR",
          files: {
            "README.md" => "# 50 Review Threads PR\n\nThis will have many review threads."
          }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting files for review threads..."
        head_ref.append_commit({ message: "Add files for 50 review threads", committer: author, author: author }, author) do |changes|
          # Create files with enough lines to support 50 review threads
          # Each file gets 25 lines, and we'll create 2 files = 50 possible line positions
          2.times do |i|
            content = (1..25).map { |n| "File #{i} line #{n} for review thread" }.join("\n")
            changes.add("review_files/file_#{i}.rb", content)
          end
        end

        puts "\t\tOpening PR..."
        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with 50 review threads",
          body: "This pull request will have 50 review threads for testing.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )

        puts "\t\tAdding 50 review threads..."
        # Create review threads across all files and lines
        2.times do |file_index|
          25.times do |line_number|
            create_pull_request_review_thread(
              pull: pull,
              possible_commenter_ids: possible_commenter_ids,
              position_options: {
                path: "review_files/file_#{file_index}.rb",
                side: :right,
                line: line_number + 1
              }
            )
          end
        end
      end

      def self.seed_multiple_file_types_pr(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "multiple-file-types-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for multiple file types PR",
          files: {
            "README.md" => "# Multiple File Types PR\n\nDemonstrating various file types.",
            "existing.js" => "// Existing JavaScript\nconsole.log('hello');"
          }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting multiple file types..."
        head_ref.append_commit({ message: "Add and modify multiple file types", committer: author, author: author }, author) do |changes|
          # JavaScript files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("src/javascript/module_#{i}.js", generate_javascript_code(i, lines))
          end

          # C++ files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("src/cpp/processor_#{i}.cpp", generate_cpp_code(i, lines))
          end

          # Shell scripts (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("scripts/deploy_#{i}.sh", generate_shell_code(i, lines))
          end

          # CSS files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("styles/component_#{i}.css", generate_css_code(i, lines))
          end

          # Go files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("pkg/golang/handler_#{i}.go", generate_go_code(i, lines))
          end

          # Java files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("src/java/Manager_#{i}.java", generate_java_code(i, lines))
          end

          # Ruby files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("lib/ruby/class_#{i}.rb", generate_ruby_code(i, lines))
          end

          # Python files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("src/python/service_#{i}.py", generate_python_code(i, lines))
          end

          # XML files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<configuration>\n  <service id=\"#{i}\">\n    <name>Service #{i}</name>\n"
            (lines - 10).times do |j|
              content += "    <setting key=\"config_#{j}\">value_#{j}</setting>\n"
            end
            content += "  </service>\n  <metadata>\n    <author>GitHub</author>\n    <version>1.0.0</version>\n  </metadata>\n</configuration>"
            changes.add("config/service_#{i}.xml", content)
          end

          # YAML files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("config/service_#{i}.yaml", generate_yaml_code(i, lines))
          end

          # Text files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            content = "Project Documentation #{i}\n" + "=" * 30 + "\n\n"
            (lines - 5).times do |j|
              content += "Section #{j}: This is detailed information about feature #{j} in document #{i}.\n"
            end
            content += "\nEnd of document #{i}\n"
            changes.add("docs/document_#{i}.txt", content)
          end

          # MDX files (5 files, 30-120 lines each)
          5.times do |i|
            lines = 30 + rand(91)
            changes.add("docs/guide_#{i}.mdx", generate_markdown_code(i, lines))
          end
        end

        puts "\t\tOpening PR with multiple file types..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with 60 files across 12 languages (30-120 lines each)",
          body: "This pull request demonstrates 60 files across 12 programming languages with realistic code (30-120 lines per file):\n\n- JavaScript (5 files)\n- C++ (5 files)\n- Shell (5 files)\n- CSS (5 files)\n- Go (5 files)\n- Java (5 files)\n- Ruby (5 files)\n- Python (5 files)\n- XML (5 files)\n- YAML (5 files)\n- Text (5 files)\n- MDX (5 files)\n\nTotal: 60 files with varied realistic code",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      def self.seed_multilanguage_p95_pr(repo:, author:, reviewer_user_ids:, possible_commenter_ids:, draft: false)
        base_branch_name = "massive-multilang-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting initial files to base branch #{base_branch_name}..."

        # Create base files to be modified (to generate realistic diffs with context)
        # More than half (300+) of the 500 files will exist in base to show modifications
        base_files = {}

        # Create 300+ base files across all 20 languages that will be modified in the PR
        # This represents existing code being updated
        files_per_language = 25
        languages_to_modify = 15 # 15 languages * 25 = 375 files in base (75% of 500)

        languages_to_modify.times do |lang_idx|
          files_per_language.times do |file_idx|
            i = lang_idx * files_per_language + file_idx
            # Generate 3-6x more content with randomization
            size_multiplier = 3 + rand(4) # 3-6x
            num_methods = 3 + rand(8) # 3-10 methods

            case lang_idx % 15
            when 0 # Ruby
              code = "# frozen_string_literal: true\n\n"
              code += "# Service class for feature #{i}\n"
              code += "class Service#{i}\n"
              code += "  attr_reader :data, :config, :status\n\n"
              code += "  def initialize(config = {})\n"
              code += "    @data = []\n"
              code += "    @config = config\n"
              code += "    @status = :initialized\n"
              code += "    @logger = Logger.new(STDOUT)\n"
              code += "  end\n\n"
              num_methods.times do |m|
                code += "  def process_#{m}(input)\n"
                code += "    @logger.info('Processing method #{m}')\n"
                code += "    result = transform_#{m}(input)\n"
                code += "    @data << result\n"
                code += "    result\n"
                code += "  end\n\n"
              end
              code += "  private\n\n"
              num_methods.times do |m|
                code += "  def transform_#{m}(input)\n"
                code += "    # Transform logic for method #{m}\n"
                code += "    input.to_s.upcase\n"
                code += "  end\n\n"
              end
              code += "end\n"
              base_files["lib/ruby/class_#{i}.rb"] = code

            when 1 # JavaScript
              code = "// Component #{i} - Feature implementation\n"
              code += "const EventEmitter = require('events');\n\n"
              code += "class Component#{i} extends EventEmitter {\n"
              code += "  constructor(config = {}) {\n"
              code += "    super();\n"
              code += "    this.data = [];\n"
              code += "    this.config = config;\n"
              code += "    this.status = 'initialized';\n"
              code += "  }\n\n"
              num_methods.times do |m|
                code += "  async process#{m}(input) {\n"
                code += "    console.log('Processing #{m}:', input);\n"
                code += "    const result = await this.transform#{m}(input);\n"
                code += "    this.data.push(result);\n"
                code += "    this.emit('processed', result);\n"
                code += "    return result;\n"
                code += "  }\n\n"
              end
              num_methods.times do |m|
                code += "  transform#{m}(input) {\n"
                code += "    return Promise.resolve(String(input).toUpperCase());\n"
                code += "  }\n\n"
              end
              code += "}\n\nmodule.exports = Component#{i};\n"
              base_files["src/javascript/module_#{i}.js"] = code

            when 2 # Python
              code = "#!/usr/bin/env python3\n"
              code += "\"\"\"Module #{i} - Service implementation\"\"\"\n\n"
              code += "from typing import List, Any\n"
              code += "import logging\n\n"
              code += "logger = logging.getLogger(__name__)\n\n"
              code += "class Module#{i}:\n"
              code += "    def __init__(self, config=None):\n"
              code += "        self.data: List[Any] = []\n"
              code += "        self.config = config or {}\n"
              code += "        self.status = 'initialized'\n"
              code += "        logger.info(f'Module#{i} initialized')\n\n"
              num_methods.times do |m|
                code += "    def process_#{m}(self, input_data):\n"
                code += "        logger.debug(f'Processing #{m}: {input_data}')\n"
                code += "        result = self._transform_#{m}(input_data)\n"
                code += "        self.data.append(result)\n"
                code += "        return result\n\n"
              end
              num_methods.times do |m|
                code += "    def _transform_#{m}(self, data):\n"
                code += "        return str(data).upper()\n\n"
              end
              base_files["src/python/service_#{i}.py"] = code

            when 3 # Java
              code = "package com.github.services;\n\n"
              code += "import java.util.List;\n"
              code += "import java.util.ArrayList;\n"
              code += "import java.util.logging.Logger;\n\n"
              code += "public class Handler#{i} {\n"
              code += "    private static final Logger logger = Logger.getLogger(Handler#{i}.class.getName());\n"
              code += "    private List<String> data;\n"
              code += "    private String status;\n"
              code += "    private String name;\n\n"
              code += "    public Handler#{i}() {\n"
              code += "        this.data = new ArrayList<>();\n"
              code += "        this.status = \"initialized\";\n"
              code += "        this.name = \"Handler#{i}\";\n"
              code += "    }\n\n"
              num_methods.times do |m|
                code += "    public String process#{m}(String input) {\n"
                code += "        logger.info(\"Processing #{m}: \" + input);\n"
                code += "        String result = transform#{m}(input);\n"
                code += "        data.add(result);\n"
                code += "        return result;\n"
                code += "    }\n\n"
              end
              num_methods.times do |m|
                code += "    private String transform#{m}(String input) {\n"
                code += "        return input.toUpperCase();\n"
                code += "    }\n\n"
              end
              code += "}\n"
              base_files["src/java/Manager#{i}.java"] = code

            when 4 # Go
              code = "package handler\n\n"
              code += "import (\n"
              code += "    \"fmt\"\n"
              code += "    \"strings\"\n"
              code += "    \"sync\"\n"
              code += ")\n\n"
              code += "type Handler#{i} struct {\n"
              code += "    data   []string\n"
              code += "    status string\n"
              code += "    mu     sync.RWMutex\n"
              code += "}\n\n"
              code += "func NewHandler#{i}() *Handler#{i} {\n"
              code += "    return &Handler#{i}{\n"
              code += "        data:   make([]string, 0),\n"
              code += "        status: \"initialized\",\n"
              code += "    }\n"
              code += "}\n\n"
              num_methods.times do |m|
                code += "func (h *Handler#{i}) Process#{m}(input string) string {\n"
                code += "    h.mu.Lock()\n"
                code += "    defer h.mu.Unlock()\n"
                code += "    result := h.transform#{m}(input)\n"
                code += "    h.data = append(h.data, result)\n"
                code += "    fmt.Printf(\"Processed #{m}: %s\\n\", result)\n"
                code += "    return result\n"
                code += "}\n\n"
              end
              num_methods.times do |m|
                code += "func (h *Handler#{i}) transform#{m}(input string) string {\n"
                code += "    return strings.ToUpper(input)\n"
                code += "}\n\n"
              end
              base_files["pkg/golang/handler_#{i}.go"] = code

            when 5 # TypeScript
              code = "// Interface #{i} - TypeScript service\n"
              code += "import { EventEmitter } from 'events';\n\n"
              code += "interface Config {\n"
              code += "  name?: string;\n"
              code += "  timeout?: number;\n"
              code += "}\n\n"
              code += "export class Service#{i} extends EventEmitter {\n"
              code += "  private data: string[] = [];\n"
              code += "  private config: Config;\n"
              code += "  private status: string;\n\n"
              code += "  constructor(config: Config = {}) {\n"
              code += "    super();\n"
              code += "    this.config = config;\n"
              code += "    this.status = 'initialized';\n"
              code += "  }\n\n"
              num_methods.times do |m|
                code += "  public async process#{m}(input: string): Promise<string> {\n"
                code += "    const result = this.transform#{m}(input);\n"
                code += "    this.data.push(result);\n"
                code += "    this.emit('process#{m}', result);\n"
                code += "    return result;\n"
                code += "  }\n\n"
              end
              num_methods.times do |m|
                code += "  private transform#{m}(input: string): string {\n"
                code += "    return input.toUpperCase();\n"
                code += "  }\n\n"
              end
              code += "}\n"
              base_files["src/typescript/interface_#{i}.ts"] = code

            when 6 # C++
              code = "// Processor #{i}\n"
              code += "#include <iostream>\n"
              code += "#include <string>\n"
              code += "#include <vector>\n"
              code += "#include <algorithm>\n\n"
              code += "class Processor#{i} {\n"
              code += "private:\n"
              code += "    std::vector<std::string> data;\n"
              code += "    std::string status;\n\n"
              num_methods.times do |m|
                code += "    std::string transform#{m}(const std::string& input) {\n"
                code += "        std::string result = input;\n"
                code += "        std::transform(result.begin(), result.end(), result.begin(), ::toupper);\n"
                code += "        return result;\n"
                code += "    }\n\n"
              end
              code += "public:\n"
              code += "    Processor#{i}() : status(\"initialized\") {}\n\n"
              num_methods.times do |m|
                code += "    std::string process#{m}(const std::string& input) {\n"
                code += "        std::string result = transform#{m}(input);\n"
                code += "        data.push_back(result);\n"
                code += "        std::cout << \"Processed #{m}: \" << result << std::endl;\n"
                code += "        return result;\n"
                code += "    }\n\n"
              end
              code += "};\n"
              base_files["src/cpp/processor_#{i}.cpp"] = code

            when 7 # C#
              code = "using System;\n"
              code += "using System.Collections.Generic;\n"
              code += "using System.Linq;\n\n"
              code += "namespace GitHub.Services\n"
              code += "{\n"
              code += "    public class Service#{i}\n"
              code += "    {\n"
              code += "        private List<string> data;\n"
              code += "        private string status;\n\n"
              code += "        public Service#{i}()\n"
              code += "        {\n"
              code += "            data = new List<string>();\n"
              code += "            status = \"initialized\";\n"
              code += "        }\n\n"
              num_methods.times do |m|
                code += "        public string Process#{m}(string input)\n"
                code += "        {\n"
                code += "            var result = Transform#{m}(input);\n"
                code += "            data.Add(result);\n"
                code += "            Console.WriteLine($\"Processed #{m}: {result}\");\n"
                code += "            return result;\n"
                code += "        }\n\n"
              end
              num_methods.times do |m|
                code += "        private string Transform#{m}(string input)\n"
                code += "        {\n"
                code += "            return input.ToUpper();\n"
                code += "        }\n\n"
              end
              code += "    }\n"
              code += "}\n"
              base_files["src/csharp/Service#{i}.cs"] = code

            when 8 # PHP
              code = "<?php\n\n"
              code += "namespace GitHub\\Controllers;\n\n"
              code += "class Controller#{i}\n"
              code += "{\n"
              code += "    private array $data = [];\n"
              code += "    private string $status;\n\n"
              code += "    public function __construct()\n"
              code += "    {\n"
              code += "        $this->status = 'initialized';\n"
              code += "    }\n\n"
              num_methods.times do |m|
                code += "    public function process#{m}(string $input): string\n"
                code += "    {\n"
                code += "        $result = $this->transform#{m}($input);\n"
                code += "        $this->data[] = $result;\n"
                code += "        error_log(\"Processed #{m}: $result\");\n"
                code += "        return $result;\n"
                code += "    }\n\n"
              end
              num_methods.times do |m|
                code += "    private function transform#{m}(string $input): string\n"
                code += "    {\n"
                code += "        return strtoupper($input);\n"
                code += "    }\n\n"
              end
              code += "}\n"
              base_files["src/php/Controller#{i}.php"] = code

            when 9 # Rust
              code = "use std::collections::Vec;\n\n"
              code += "pub struct Module#{i} {\n"
              code += "    data: Vec<String>,\n"
              code += "    status: String,\n"
              code += "}\n\n"
              code += "impl Module#{i} {\n"
              code += "    pub fn new() -> Self {\n"
              code += "        Module#{i} {\n"
              code += "            data: Vec::new(),\n"
              code += "            status: String::from(\"initialized\"),\n"
              code += "        }\n"
              code += "    }\n\n"
              num_methods.times do |m|
                code += "    pub fn process_#{m}(&mut self, input: &str) -> String {\n"
                code += "        let result = self.transform_#{m}(input);\n"
                code += "        self.data.push(result.clone());\n"
                code += "        println!(\"Processed #{m}: {}\", result);\n"
                code += "        result\n"
                code += "    }\n\n"
              end
              num_methods.times do |m|
                code += "    fn transform_#{m}(&self, input: &str) -> String {\n"
                code += "        input.to_uppercase()\n"
                code += "    }\n\n"
              end
              code += "}\n"
              base_files["src/rust/module_#{i}.rs"] = code

            when 10 # Swift
              code = "import Foundation\n\n"
              code += "class Model#{i} {\n"
              code += "    private var data: [String] = []\n"
              code += "    private var status: String\n\n"
              code += "    init() {\n"
              code += "        self.status = \"initialized\"\n"
              code += "    }\n\n"
              num_methods.times do |m|
                code += "    func process#{m}(input: String) -> String {\n"
                code += "        let result = transform#{m}(input: input)\n"
                code += "        data.append(result)\n"
                code += "        print(\"Processed #{m}: \\(result)\")\n"
                code += "        return result\n"
                code += "    }\n\n"
              end
              num_methods.times do |m|
                code += "    private func transform#{m}(input: String) -> String {\n"
                code += "        return input.uppercased()\n"
                code += "    }\n\n"
              end
              code += "}\n"
              base_files["src/swift/Model#{i}.swift"] = code

            when 11 # Kotlin
              code = "package com.github.repository\n\n"
              code += "class Repository#{i} {\n"
              code += "    private val data = mutableListOf<String>()\n"
              code += "    private var status: String = \"initialized\"\n\n"
              num_methods.times do |m|
                code += "    fun process#{m}(input: String): String {\n"
                code += "        val result = transform#{m}(input)\n"
                code += "        data.add(result)\n"
                code += "        println(\"Processed #{m}: $result\")\n"
                code += "        return result\n"
                code += "    }\n\n"
              end
              num_methods.times do |m|
                code += "    private fun transform#{m}(input: String): String {\n"
                code += "        return input.uppercase()\n"
                code += "    }\n\n"
              end
              code += "}\n"
              base_files["src/kotlin/Repository#{i}.kt"] = code

            when 12 # Scala
              code = "package com.github.actor\n\n"
              code += "import scala.collection.mutable.ListBuffer\n\n"
              code += "class Actor#{i} {\n"
              code += "  private val data = ListBuffer[String]()\n"
              code += "  private var status: String = \"initialized\"\n\n"
              num_methods.times do |m|
                code += "  def process#{m}(input: String): String = {\n"
                code += "    val result = transform#{m}(input)\n"
                code += "    data += result\n"
                code += "    println(s\"Processed #{m}: $result\")\n"
                code += "    result\n"
                code += "  }\n\n"
              end
              num_methods.times do |m|
                code += "  private def transform#{m}(input: String): String = {\n"
                code += "    input.toUpperCase\n"
                code += "  }\n\n"
              end
              code += "}\n"
              base_files["src/scala/Actor#{i}.scala"] = code

            when 13 # Shell
              code = "#!/bin/bash\n"
              code += "# deploy_#{i}.sh - Deployment script\n\n"
              code += "set -euo pipefail\n\n"
              code += "SERVICE_NAME=\"service_#{i}\"\n"
              code += "DEPLOY_ENV=\"${DEPLOY_ENV:-production}\"\n"
              code += "LOG_FILE=\"/var/log/${SERVICE_NAME}.log\"\n\n"
              code += "log() {\n"
              code += "    echo \"[$(date +'%Y-%m-%d %H:%M:%S')] $*\" | tee -a \"$LOG_FILE\"\n"
              code += "}\n\n"
              num_methods.times do |m|
                code += "process_#{m}() {\n"
                code += "    log \"Processing step #{m}\"\n"
                code += "    local input=\"$1\"\n"
                code += "    echo \"$input\" | tr '[:lower:]' '[:upper:]'\n"
                code += "}\n\n"
              end
              code += "main() {\n"
              code += "    log \"Starting deployment for $SERVICE_NAME\"\n"
              (num_methods / 2).times do |m|
                code += "    process_#{m} \"data_#{m}\"\n"
              end
              code += "    log \"Deployment complete\"\n"
              code += "}\n\n"
              code += "main \"$@\"\n"
              base_files["scripts/deploy_#{i}.sh"] = code

            when 14 # SQL
              code = "-- Migration #{i}\n"
              code += "BEGIN;\n\n"
              code += "CREATE TABLE IF NOT EXISTS service_#{i}_data (\n"
              code += "    id BIGSERIAL PRIMARY KEY,\n"
              code += "    name VARCHAR(255) NOT NULL,\n"
              code += "    status VARCHAR(50) DEFAULT 'active',\n"
              code += "    data JSONB,\n"
              code += "    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,\n"
              code += "    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP\n"
              code += ");\n\n"
              num_methods.times do |m|
                code += "CREATE INDEX idx_service_#{i}_field_#{m} ON service_#{i}_data(status, created_at);\n"
              end
              code += "\n"
              (num_methods / 2).times do |m|
                code += "INSERT INTO service_#{i}_data (name, status, data) VALUES\n"
                code += "    ('Sample #{m}', 'active', '{\"key\": \"value#{m}\"}');\n"
              end
              code += "\nCOMMIT;\n"
              base_files["db/migrations/migration_#{i}.sql"] = code
            end
          end
        end

        base_files["README.md"] = "# Massive Multi-Language PR\n\nThis PR demonstrates 500 files across 20 programming languages."

        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for massive multi-language PR",
          files: base_files
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting changes to all base files with large hunks (50+ additions, 8+ deletions per hunk)..."
        head_ref.append_commit({ message: "Modify all #{base_files.size} files with realistic changes (2-4 large hunks per file)", committer: author, author: author }, author) do |changes|
          total_lines = 0
          total_files = 0
          total_additions = 0
          total_deletions = 0

          # Iterate through all base files and modify each one
          base_files.each do |file_path, original_content|
            next if file_path == "README.md" # Skip README

            # Split original content into lines
            lines = original_content.lines
            next if lines.empty?

            # Determine number of hunks (4 per file) - targeting ~50 diff lines per file for 10k total
            num_hunks = 3

            # Create modified content with multiple hunks
            modified_lines = lines.dup
            hunks_created = 0
            last_position = 0

            num_hunks.times do |hunk_num|
              # Ensure hunks are at least 10 lines apart
              min_position = last_position + 10
              max_position = [modified_lines.size - 15, min_position + 5].max

              # Skip if there's not enough space for this hunk
              next if max_position < min_position

              position = rand(min_position..max_position)

              # Each hunk will have both additions and deletions
              # Target: 6 additions and 4 deletions per hunk for 12 diff lines per hunk
              # With 4 hunks per file: 4 × 12 = 48 diff lines per file
              # 210 modified files × 48 = 10,080 total diff lines

              # Delete 4 lines first
              deletion_count = 4
              deletion_count = [deletion_count, modified_lines.size - position - 5].min

              if deletion_count > 0
                deletion_count.times do
                  modified_lines.delete_at(position) if position < modified_lines.size
                end
                total_deletions += deletion_count
              end

              # Add 6 new lines at the same position
              addition_count = 6
              new_lines = []

              # Generate realistic code additions based on file type
              if file_path.end_with?(".rb")
                new_lines << "  # New method added in hunk #{hunk_num + 1}\n"
                new_lines << "  def process_data_#{hunk_num}(input)\n"
                addition_count.times do |i|
                  case i % 5
                  when 0
                    new_lines << "    # Process step #{i + 1}\n"
                  when 1
                    new_lines << "    result_#{i} = transform(input)\n"
                  when 2
                    new_lines << "    @logger.debug(\"Processing #{i}: \#{result_#{i}}\")\n"
                  when 3
                    new_lines << "    validate_result(result_#{i})\n"
                  when 4
                    new_lines << "    @data << result_#{i}\n"
                  end
                end
                new_lines << "    result\n"
                new_lines << "  end\n\n"
              elsif file_path.end_with?(".js", ".ts")
                new_lines << "  // New method added in hunk #{hunk_num + 1}\n"
                new_lines << "  async processData#{hunk_num}(input) {\n"
                addition_count.times do |i|
                  case i % 5
                  when 0
                    new_lines << "    // Process step #{i + 1}\n"
                  when 1
                    new_lines << "    const result#{i} = await this.transform(input);\n"
                  when 2
                    new_lines << "    console.debug(`Processing #{i}: ${result#{i}}`);\n"
                  when 3
                    new_lines << "    this.validateResult(result#{i});\n"
                  when 4
                    new_lines << "    this.data.push(result#{i});\n"
                  end
                end
                new_lines << "    return result;\n"
                new_lines << "  }\n\n"
              elsif file_path.end_with?(".py")
                new_lines << "    # New method added in hunk #{hunk_num + 1}\n"
                new_lines << "    def process_data_#{hunk_num}(self, input: Any) -> Any:\n"
                addition_count.times do |i|
                  case i % 5
                  when 0
                    new_lines << "        # Process step #{i + 1}\n"
                  when 1
                    new_lines << "        result_#{i} = self.transform(input)\n"
                  when 2
                    new_lines << "        logger.debug(f'Processing #{i}: {result_#{i}}')\n"
                  when 3
                    new_lines << "        self.validate_result(result_#{i})\n"
                  when 4
                    new_lines << "        self.data.append(result_#{i})\n"
                  end
                end
                new_lines << "        return result\n\n"
              else
                # Generic additions for other file types
                new_lines << "    // New code block added in hunk #{hunk_num + 1}\n"
                addition_count.times do |i|
                  new_lines << "    var step#{i} = process(data);\n"
                end
                new_lines << "\n"
              end

              modified_lines.insert(position, *new_lines)
              total_additions += new_lines.size
              hunks_created += 1

              # Update last position to enforce spacing
              last_position = position + new_lines.size
            end

            # Only add the change if we actually created hunks
            if hunks_created > 0
              new_content = modified_lines.join
              changes.add(file_path, new_content)
              total_lines += new_content.lines.count
              total_files += 1
            end
          end

          # Also add the README with updated content
          changes.add("README.md", "# Massive Multi-Language PR\n\nThis PR demonstrates #{base_files.size} files across 20 programming languages with realistic modifications.\n\nEach file has been modified with 4 hunks:\n- 8 additions per hunk\n- 4 deletions per hunk\n- 12 diff lines per hunk\n- Hunks spaced at least 10 lines apart\n- Targeting ~10,000 total diff lines across 280 files\n\nTotal changes: ~#{total_additions} additions, ~#{total_deletions} deletions across #{total_files} files")

          puts "\t\t\tModified #{total_files} files targeting 10k diff lines (~#{total_additions} additions, ~#{total_deletions} deletions, ~#{total_additions + total_deletions} total diff lines)"
        end

        puts "\t\tOpening PR with 280 files..."
        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Massive PR: 280 files across 20 languages with 10k+ LOC changes",
          body: "This pull request demonstrates:\n\n- 280 files across 20 programming languages (210 modified, 70 new)\n- 10,000-12,000 lines of changes\n- Realistic code with additions, deletions, and modifications\n- 50 review comments across different files\n\nLanguages included: Ruby, JavaScript, Python, Java, Go, TypeScript, C++, C#, PHP, Rust, Swift, Kotlin, Scala, Shell, SQL, CSS/SCSS, HTML, YAML, JSON, Markdown\n\nModified languages: Ruby, JavaScript, Python, Java, Go, TypeScript, C++, C#, PHP, Rust, Swift, Kotlin, Scala, Shell, SQL\nNew files: CSS/SCSS, HTML, YAML, JSON, Markdown",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      def self.seed_comments_outside_the_diff_pr(repo:, author:, reviewer_user_ids:, possible_commenter_ids:, draft: false)
        base_branch_name = "comments-outside-diff-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting changes to base branch #{base_branch_name}..."
        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Initial commit for comments outside diff PR",
          files: {
            "README.md" => "# Comments Outside Diff PR\n\nThis PR will have comments outside the diff.",
            "main.rb" => (1..10).map { |n| "# Line #{n}: Original implementation\ndef method_#{n}\n  puts 'original method #{n}'\nend\n" }.join("\n"),
          }
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting changes to create comments outside the diff..."
        head_ref.append_commit({ message: "Add files for comments outside diff", committer: author, author: author }, author) do |changes|
          # Modify only a small portion of main.rb to create a specific diff area
          # This will allow us to add comments outside the visible diff
          changes.add("main.rb", (1..10).map do |n|
            if n >= 3 && n <= 5
              # Only modify lines 10-20 to create a focused diff area
              "# Line #{n}: MODIFIED implementation\ndef method_#{n}(param = nil)\n  puts 'modified method #{n}'\n  return param\nend\n"
            else
              # Keep other lines the same
              "# Line #{n}: Original implementation\ndef method_#{n}\n  puts 'original method #{n}'\nend\n"
            end
          end.join("\n"))
        end

        puts "\t\tOpening PR with comments outside the diff..."
        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with comments outside the diff",
          body: "This pull request will have comments outside the diff.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )

        puts "\t\tAdding a comment within the diff area..."
        create_pull_request_review_thread(
          pull: pull,
          possible_commenter_ids: possible_commenter_ids,
          position_options: {
             path: "main.rb",
             side: :right,
             line: 20 # This line is within the diff area we modified
          },
        )

        puts "\t\tAdding a comment outside the diff..."
        pull_comparison = ::PullRequest::Comparison.find(pull: pull,
          start_commit_oid: pull.merge_base,
          end_commit_oid: pull.head_sha,
          base_commit_oid: pull.merge_base)

        # Using the method we defined above instead of PullRequests::ReviewComments::Create
        create_pull_request_review_thread_outside_of_diff(
          pull: pull,
          comparison: pull_comparison,
          possible_commenter_ids: possible_commenter_ids,
          positioning: {
              type: "line",
              line: "6",
              commit_oid: pull_comparison.end_commit.oid,
              path: "main.rb"
            }
        )

        puts "\t\tDone!\n"
      end

      # Creates a PR that contains one small change (5 lines) and another file
      # that is removed entirely and contains 6000 lines in the base. This
      # produces a single big deletion delta and a small modification delta.
      def self.seed_pr_single_deletion_6000(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "single-deletion-6000-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting base content for single-file 6000-line deletion PR..."
        base_files = {
          "small_context.rb" => (1..10).map { |n| "line \\#{n} original" }.join("\n"),
          "deleted_large_file.rb" => (1..6000).map { |n| "deleted line \\#{n}" }.join("\n")
        }

        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Base for single-file 6000-line deletion PR",
          files: base_files
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting head changes (small modification + deletion)..."
        head_ref.append_commit({ message: "Remove large file and tweak small file", committer: author, author: author }, author) do |changes|
          # Modify a small file with a 5-line tweak
          changes.add("small_context.rb", (1..5).map { |n| "small change line \\#{n}" }.join("\n"))

          # Remove the large file entirely to create a single deletion delta
          changes.remove("deleted_large_file.rb")
        end

        puts "\t\tOpening PR for single-file deletion..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "PR: small change + single-file deletion of 6000 lines",
          body: "Contains one small file change and one large file removal (6000 lines) to exercise deletion handling.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      # Creates a PR that contains one small change (5 lines) and deletes 6000
      # lines across 4 separate files so that the deletion is represented as
      # four diff deltas (one per removed file).
      def self.seed_pr_deletion_6000_over_4_diffs(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "multi-deletion-6000-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting base content for 4-way 6000-line deletion PR..."
        # Create 4 files with ~1500 lines each
        base_files = {}
        4.times do |i|
          base_files["deleted_chunk_#{i}.rb"] = (1..1500).map { |n| "chunk #{i} line \\#{n}" }.join("\n")
        end
        base_files["small_context.rb"] = (1..10).map { |n| "line \\#{n} original" }.join("\n")

        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Base for 4-way 6000-line deletion PR",
          files: base_files
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting head changes (small modification + four removals)..."
        head_ref.append_commit({ message: "Remove 4 large chunks and tweak small file", committer: author, author: author }, author) do |changes|
          # Modify the small file (5-line change)
          changes.add("small_context.rb", (1..5).map { |n| "small change line \\#{n}" }.join("\n"))

          # Remove each large chunk file to create four delete deltas
          4.times do |i|
            changes.remove("deleted_chunk_#{i}.rb")
          end
        end

        puts "\t\tOpening PR for 4-way deletion..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "PR: small change + deletion of 6000 lines over 4 diffs",
          body: "Contains one small file change and four deletions totaling ~6000 lines to exercise multi-delta deletion handling.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      # Creates a PR that contains one very large modification (>5000 changed
      # lines) and one small modification of 5 lines. This creates two diffs in
      # the same PR: one huge and one small.
      def self.seed_pr_huge_5000_and_small_5(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "huge-5000-plus-base-#{SecureRandom.hex}"
        head_branch_name = "#{base_branch_name}-updates-#{SecureRandom.hex}"

        puts "\t\tCommitting base content for huge-5000+ PR..."
        base_files = {
          "huge_changed_file.rb" => (1..5_100).map { |n| "original huge line \\#{n}" }.join("\n"),
          "small_change_file.rb" => (1..10).map { |n| "line \\#{n} original" }.join("\n")
        }

        base_commit = Seeds::Objects::Commit.create(
          repo: repo,
          committer: author,
          branch_name: base_branch_name,
          from_branch: repo.default_branch,
          message: "Base for huge-5000+ PR",
          files: base_files
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_commit.oid, author)

        puts "\t\tCommitting head changes (huge rewrite + small tweak)..."
        head_ref.append_commit({ message: "Rewrite huge file and tweak small file", committer: author, author: author }, author) do |changes|
          # Rewrite the huge file creating >5000 changed lines
          changes.add("huge_changed_file.rb", (1..5_100).map { |n| "updated huge line \\#{n}" }.join("\n"))

          # Modify the small file with a 5-line change
          changes.add("small_change_file.rb", (1..5).map { |n| "small change line \\#{n}" }.join("\n"))
        end

        puts "\t\tOpening PR for huge change + small change..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "PR: huge >5000-line change + small 5-line change",
          body: "Contains one very large diff and one small diff to exercise combined thresholds.",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )
      end

      # Creates a PR with several diff hunks, primarily for use with pull request groups
      def self.seed_pr_with_several_diff_hunks(repo:, author:, reviewer_user_ids:, draft: false)
        base_branch_name = "main"
        head_branch_name = "calculator-changes-#{SecureRandom.hex}"

        base_ref = Seeds::Objects::Commit.create(
          branch_name: base_branch_name,
          committer: author,
          date: 2.days.ago.iso8601,
          message: "Base commit for PR with several diff hunks",
          repo: repo,
        )

        puts "\t\tCreating head branch #{head_branch_name}..."
        head_ref = repo.refs.create("refs/heads/#{head_branch_name}", base_ref.oid, author)

        puts "\t\tUpdate contents of calculator file"
        head_ref.append_commit({ message: "Update calculator", committer: author, author: author }, author) do |changes|
          changes.add("groups/calculator.rb", edited_calculator_file_contents)
        end

        puts "\t\tUpdate contents of readme file"
        head_ref.append_commit({ message: "Update readme", committer: author, author: author }, author) do |changes|
          changes.add("README.md", "# Calculator Application\n\nThis application provides a simple calculator with various operations.")
        end

        puts "\t\tOpening PR with several diff hunks..."
        pull = ::PullRequest.create_for!(
          repo,
          user: author,
          title: "PR with several hunks in calculator file",
          body: "Changes calculator file",
          head: head_ref.name,
          base: base_branch_name,
          reviewer_user_ids: reviewer_user_ids,
          draft: draft,
        )

        puts "\t\tAdding comments to PR with several diff hunks..."
        create_pull_request_review_thread(pull: pull, possible_commenter_ids: reviewer_user_ids, position_options: { path: "groups/calculator.rb", side: :right, line: 31 })
        create_pull_request_review_thread(pull: pull, possible_commenter_ids: reviewer_user_ids, position_options: { path: "groups/calculator.rb", side: :left, line: 107 })
        create_pull_request_groups(pull: pull)
      end

      # Code generation helpers for multiple languages
      def self.generate_ruby_code(index, lines)
        class_name = "Service#{index}"
        methods = (lines / 5).clamp(2, 8)
        code = "# frozen_string_literal: true\n\n"
        code += "# #{class_name} - Handles business logic for feature #{index}\n"
        code += "class #{class_name}\n"
        code += "  attr_reader :data, :config\n\n"
        code += "  def initialize(config = {})\n"
        code += "    @data = []\n"
        code += "    @config = config\n"
        code += "    @logger = Logger.new(STDOUT)\n"
        code += "  end\n\n"
        methods.times do |i|
          code += "  def process_#{i}(input)\n"
          code += "    @logger.info('Processing input')\n"
          code += "    result = transform_#{i}(input)\n"
          code += "    @data << result\n"
          code += "    result\n"
          code += "  end\n\n"
        end
        code += "  private\n\n"
        code += "  def transform_0(input)\n"
        code += "    input.to_s.upcase\n"
        code += "  end\n"
        code += "end\n"
        code
      end

      def self.generate_javascript_code(index, lines)
        class_name = "Module#{index}"
        methods = (lines / 4).clamp(2, 8)
        code = "// #{class_name} - Business logic module\n"
        code += "const EventEmitter = require('events');\n\n"
        code += "class #{class_name} extends EventEmitter {\n"
        code += "  constructor(config = {}) {\n"
        code += "    super();\n"
        code += "    this.data = [];\n"
        code += "    this.config = config;\n"
        code += "  }\n\n"
        methods.times do |i|
          code += "  process#{i}(input) {\n"
          code += "    this.emit('processing', input);\n"
          code += "    const result = this.transform#{i}(input);\n"
          code += "    this.data.push(result);\n"
          code += "    return result;\n"
          code += "  }\n\n"
        end
        code += "  transform0(input) {\n"
        code += "    return String(input).toUpperCase();\n"
        code += "  }\n"
        code += "}\n\n"
        code += "module.exports = #{class_name};\n"
        code
      end

      def self.generate_python_code(index, lines)
        class_name = "Service#{index}"
        methods = (lines / 5).clamp(2, 8)
        code = "#!/usr/bin/env python3\n"
        code += "\"\"\"#{class_name} - Business logic service\"\"\"\n\n"
        code += "from typing import List, Dict, Any\n"
        code += "import logging\n\n"
        code += "logger = logging.getLogger(__name__)\n\n"
        code += "class #{class_name}:\n"
        code += "    def __init__(self, config: Dict[str, Any] = None):\n"
        code += "        self.data: List[Any] = []\n"
        code += "        self.config = config or {}\n"
        code += "        logger.info(f'#{class_name} initialized')\n\n"
        methods.times do |i|
          code += "    def process_#{i}(self, input_data: Any) -> Any:\n"
          code += "        logger.debug(f'Processing: {input_data}')\n"
          code += "        result = self.transform_#{i}(input_data)\n"
          code += "        self.data.append(result)\n"
          code += "        return result\n\n"
        end
        code += "    def transform_0(self, data: Any) -> str:\n"
        code += "        return str(data).upper()\n"
        code
      end

      def self.generate_java_code(index, lines)
        class_name = "Manager#{index}"
        methods = (lines / 6).clamp(2, 6)
        code = "package com.github.service;\n\n"
        code += "import java.util.List;\n"
        code += "import java.util.ArrayList;\n"
        code += "import java.util.logging.Logger;\n\n"
        code += "public class #{class_name} {\n"
        code += "    private static final Logger logger = Logger.getLogger(#{class_name}.class.getName());\n"
        code += "    private List<String> data;\n"
        code += "    private String status;\n\n"
        code += "    public #{class_name}() {\n"
        code += "        this.data = new ArrayList<>();\n"
        code += "        this.status = \"initialized\";\n"
        code += "    }\n\n"
        methods.times do |i|
          code += "    public String process#{i}(String input) {\n"
          code += "        logger.info(\"Processing: \" + input);\n"
          code += "        String result = transform#{i}(input);\n"
          code += "        data.add(result);\n"
          code += "        return result;\n"
          code += "    }\n\n"
        end
        code += "    private String transform0(String input) {\n"
        code += "        return input.toUpperCase();\n"
        code += "    }\n"
        code += "}\n"
        code
      end

      def self.generate_go_code(index, lines)
        methods = (lines / 5).clamp(2, 6)
        code = "package handler\n\n"
        code += "import (\n"
        code += "    \"fmt\"\n"
        code += "    \"strings\"\n"
        code += "    \"sync\"\n"
        code += ")\n\n"
        code += "type Handler#{index} struct {\n"
        code += "    data   []string\n"
        code += "    status string\n"
        code += "    mu     sync.RWMutex\n"
        code += "}\n\n"
        code += "func NewHandler#{index}() *Handler#{index} {\n"
        code += "    return &Handler#{index}{\n"
        code += "        data:   make([]string, 0),\n"
        code += "        status: \"initialized\",\n"
        code += "    }\n"
        code += "}\n\n"
        methods.times do |i|
          code += "func (h *Handler#{index}) Process#{i}(input string) string {\n"
          code += "    h.mu.Lock()\n"
          code += "    defer h.mu.Unlock()\n"
          code += "    result := h.transform#{i}(input)\n"
          code += "    h.data = append(h.data, result)\n"
          code += "    return result\n"
          code += "}\n\n"
        end
        code += "func (h *Handler#{index}) transform0(input string) string {\n"
        code += "    return strings.ToUpper(input)\n"
        code += "}\n"
        code
      end

      def self.generate_typescript_code(index, lines)
        methods = (lines / 4).clamp(2, 8)
        code = "// Interface#{index} - TypeScript service interface\n"
        code += "import { EventEmitter } from 'events';\n\n"
        code += "interface Config {\n"
        code += "  [key: string]: any;\n"
        code += "}\n\n"
        code += "export class Service#{index} extends EventEmitter {\n"
        code += "  private data: string[] = [];\n"
        code += "  private config: Config;\n\n"
        code += "  constructor(config: Config = {}) {\n"
        code += "    super();\n"
        code += "    this.config = config;\n"
        code += "  }\n\n"
        methods.times do |i|
          code += "  public process#{i}(input: string): string {\n"
          code += "    this.emit('processing', input);\n"
          code += "    const result = this.transform#{i}(input);\n"
          code += "    this.data.push(result);\n"
          code += "    return result;\n"
          code += "  }\n\n"
        end
        code += "  private transform0(input: string): string {\n"
        code += "    return input.toUpperCase();\n"
        code += "  }\n"
        code += "}\n"
        code
      end

      def self.generate_cpp_code(index, lines)
        methods = (lines / 6).clamp(2, 6)
        code = "// Processor#{index}.cpp\n"
        code += "#include <iostream>\n"
        code += "#include <string>\n"
        code += "#include <vector>\n"
        code += "#include <algorithm>\n\n"
        code += "class Processor#{index} {\n"
        code += "private:\n"
        code += "    std::vector<std::string> data;\n"
        code += "    std::string status;\n\n"
        code += "    std::string transform0(const std::string& input) {\n"
        code += "        std::string result = input;\n"
        code += "        std::transform(result.begin(), result.end(), result.begin(), ::toupper);\n"
        code += "        return result;\n"
        code += "    }\n\n"
        code += "public:\n"
        code += "    Processor#{index}() : status(\"initialized\") {}\n\n"
        methods.times do |i|
          code += "    std::string process#{i}(const std::string& input) {\n"
          code += "        std::cout << \"Processing: \" << input << std::endl;\n"
          code += "        std::string result = transform0(input);\n"
          code += "        data.push_back(result);\n"
          code += "        return result;\n"
          code += "    }\n\n"
        end
        code += "};\n"
        code
      end

      def self.generate_csharp_code(index, lines)
        methods = (lines / 5).clamp(2, 6)
        code = "using System;\n"
        code += "using System.Collections.Generic;\n"
        code += "using System.Linq;\n\n"
        code += "namespace GitHub.Services\n"
        code += "{\n"
        code += "    public class Service#{index}\n"
        code += "    {\n"
        code += "        private List<string> data;\n"
        code += "        private string status;\n\n"
        code += "        public Service#{index}()\n"
        code += "        {\n"
        code += "            data = new List<string>();\n"
        code += "            status = \"initialized\";\n"
        code += "        }\n\n"
        methods.times do |i|
          code += "        public string Process#{i}(string input)\n"
          code += "        {\n"
          code += "            Console.WriteLine($\"Processing: {input}\");\n"
          code += "            var result = Transform#{i}(input);\n"
          code += "            data.Add(result);\n"
          code += "            return result;\n"
          code += "        }\n\n"
        end
        code += "        private string Transform0(string input)\n"
        code += "        {\n"
        code += "            return input.ToUpper();\n"
        code += "        }\n"
        code += "    }\n"
        code += "}\n"
        code
      end

      def self.generate_php_code(index, lines)
        methods = (lines / 5).clamp(2, 6)
        code = "<?php\n\n"
        code += "namespace GitHub\\Controllers;\n\n"
        code += "class Controller#{index}\n"
        code += "{\n"
        code += "    private array $data = [];\n"
        code += "    private string $status;\n\n"
        code += "    public function __construct()\n"
        code += "    {\n"
        code += "        $this->status = 'initialized';\n"
        code += "    }\n\n"
        methods.times do |i|
          code += "    public function process#{i}(string $input): string\n"
          code += "    {\n"
          code += "        error_log(\"Processing: $input\");\n"
          code += "        $result = $this->transform#{i}($input);\n"
          code += "        $this->data[] = $result;\n"
          code += "        return $result;\n"
          code += "    }\n\n"
        end
        code += "    private function transform0(string $input): string\n"
        code += "    {\n"
        code += "        return strtoupper($input);\n"
        code += "    }\n"
        code += "}\n"
        code
      end

      def self.generate_rust_code(index, lines)
        methods = (lines / 5).clamp(2, 6)
        code = "// module_#{index}.rs\n"
        code += "use std::collections::Vec;\n\n"
        code += "pub struct Module#{index} {\n"
        code += "    data: Vec<String>,\n"
        code += "    status: String,\n"
        code += "}\n\n"
        code += "impl Module#{index} {\n"
        code += "    pub fn new() -> Self {\n"
        code += "        Module#{index} {\n"
        code += "            data: Vec::new(),\n"
        code += "            status: String::from(\"initialized\"),\n"
        code += "        }\n"
        code += "    }\n\n"
        methods.times do |i|
          code += "    pub fn process_#{i}(&mut self, input: &str) -> String {\n"
          code += "        println!(\"Processing: {}\", input);\n"
          code += "        let result = self.transform_#{i}(input);\n"
          code += "        self.data.push(result.clone());\n"
          code += "        result\n"
          code += "    }\n\n"
        end
        code += "    fn transform_0(&self, input: &str) -> String {\n"
        code += "        input.to_uppercase()\n"
        code += "    }\n"
        code += "}\n"
        code
      end

      def self.generate_swift_code(index, lines)
        methods = (lines / 4).clamp(2, 6)
        code = "// Model#{index}.swift\n"
        code += "import Foundation\n\n"
        code += "class Model#{index} {\n"
        code += "    private var data: [String] = []\n"
        code += "    private var status: String\n\n"
        code += "    init() {\n"
        code += "        self.status = \"initialized\"\n"
        code += "    }\n\n"
        methods.times do |i|
          code += "    func process#{i}(input: String) -> String {\n"
          code += "        print(\"Processing: \\(input)\")\n"
          code += "        let result = transform#{i}(input: input)\n"
          code += "        data.append(result)\n"
          code += "        return result\n"
          code += "    }\n\n"
        end
        code += "    private func transform0(input: String) -> String {\n"
        code += "        return input.uppercased()\n"
        code += "    }\n"
        code += "}\n"
        code
      end

      def self.generate_kotlin_code(index, lines)
        methods = (lines / 4).clamp(2, 6)
        code = "package com.github.repository\n\n"
        code += "class Repository#{index} {\n"
        code += "    private val data = mutableListOf<String>()\n"
        code += "    private var status: String = \"initialized\"\n\n"
        methods.times do |i|
          code += "    fun process#{i}(input: String): String {\n"
          code += "        println(\"Processing: $input\")\n"
          code += "        val result = transform#{i}(input)\n"
          code += "        data.add(result)\n"
          code += "        return result\n"
          code += "    }\n\n"
        end
        code += "    private fun transform0(input: String): String {\n"
        code += "        return input.uppercase()\n"
        code += "    }\n"
        code += "}\n"
        code
      end

      def self.generate_scala_code(index, lines)
        methods = (lines / 4).clamp(2, 6)
        code = "package com.github.actor\n\n"
        code += "import scala.collection.mutable.ListBuffer\n\n"
        code += "class Actor#{index} {\n"
        code += "  private val data = ListBuffer[String]()\n"
        code += "  private var status: String = \"initialized\"\n\n"
        methods.times do |i|
          code += "  def process#{i}(input: String): String = {\n"
          code += "    println(s\"Processing: $input\")\n"
          code += "    val result = transform#{i}(input)\n"
          code += "    data += result\n"
          code += "    result\n"
          code += "  }\n\n"
        end
        code += "  private def transform0(input: String): String = {\n"
        code += "    input.toUpperCase\n"
        code += "  }\n"
        code += "}\n"
        code
      end

      def self.generate_shell_code(index, lines)
        code = "#!/bin/bash\n"
        code += "# deploy_#{index}.sh - Deployment script\n\n"
        code += "set -euo pipefail\n\n"
        code += "# Configuration\n"
        code += "SERVICE_NAME=\"service_#{index}\"\n"
        code += "DEPLOY_ENV=\"${DEPLOY_ENV:-production}\"\n"
        code += "LOG_FILE=\"/var/log/${SERVICE_NAME}.log\"\n\n"
        code += "# Functions\n"
        code += "log() {\n"
        code += "    echo \"[$(date +'%Y-%m-%d %H:%M:%S')] $*\" | tee -a \"$LOG_FILE\"\n"
        code += "}\n\n"
        code += "check_dependencies() {\n"
        code += "    log \"Checking dependencies...\"\n"
        code += "    command -v docker >/dev/null 2>&1 || { log \"Docker is required\"; exit 1; }\n"
        code += "}\n\n"
        code += "deploy() {\n"
        code += "    log \"Deploying $SERVICE_NAME to $DEPLOY_ENV\"\n"
        code += "    docker-compose up -d\n"
        code += "    log \"Deployment complete\"\n"
        code += "}\n\n"
        code += "main() {\n"
        code += "    check_dependencies\n"
        code += "    deploy\n"
        code += "}\n\n"
        code += "main \"$@\"\n"
        code
      end

      def self.generate_sql_code(index, lines)
        code = "-- Migration #{index}: Add new tables and indexes\n\n"
        code += "BEGIN;\n\n"
        code += "-- Create table for service_#{index}\n"
        code += "CREATE TABLE IF NOT EXISTS service_#{index}_data (\n"
        code += "    id BIGSERIAL PRIMARY KEY,\n"
        code += "    name VARCHAR(255) NOT NULL,\n"
        code += "    status VARCHAR(50) DEFAULT 'active',\n"
        code += "    data JSONB,\n"
        code += "    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,\n"
        code += "    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP\n"
        code += ");\n\n"
        code += "-- Create indexes\n"
        code += "CREATE INDEX idx_service_#{index}_status ON service_#{index}_data(status);\n"
        code += "CREATE INDEX idx_service_#{index}_created ON service_#{index}_data(created_at);\n\n"
        code += "-- Insert sample data\n"
        code += "INSERT INTO service_#{index}_data (name, status, data) VALUES\n"
        code += "    ('Sample 1', 'active', '{\"key\": \"value1\"}'),\n"
        code += "    ('Sample 2', 'active', '{\"key\": \"value2\"}');\n\n"
        code += "COMMIT;\n"
        code
      end

      def self.generate_css_code(index, lines)
        code = "/* Component #{index} Styles */\n\n"
        code += ".component-#{index} {\n"
        code += "  display: flex;\n"
        code += "  flex-direction: column;\n"
        code += "  padding: 16px;\n"
        code += "  margin: 8px;\n"
        code += "  background-color: #ffffff;\n"
        code += "  border-radius: 8px;\n"
        code += "  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);\n\n"
        code += "  &__header {\n"
        code += "    font-size: 24px;\n"
        code += "    font-weight: bold;\n"
        code += "    color: #333333;\n"
        code += "    margin-bottom: 12px;\n"
        code += "  }\n\n"
        code += "  &__content {\n"
        code += "    font-size: 14px;\n"
        code += "    line-height: 1.6;\n"
        code += "    color: #666666;\n"
        code += "  }\n\n"
        code += "  &__button {\n"
        code += "    padding: 10px 20px;\n"
        code += "    background-color: #0366d6;\n"
        code += "    color: white;\n"
        code += "    border: none;\n"
        code += "    border-radius: 4px;\n"
        code += "    cursor: pointer;\n\n"
        code += "    &:hover {\n"
        code += "      background-color: #0256c4;\n"
        code += "    }\n"
        code += "  }\n"
        code += "}\n"
        code
      end

      def self.generate_html_code(index, lines)
        code = "<!DOCTYPE html>\n"
        code += "<html lang=\"en\">\n"
        code += "<head>\n"
        code += "    <meta charset=\"UTF-8\">\n"
        code += "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n"
        code += "    <title>Page #{index}</title>\n"
        code += "    <link rel=\"stylesheet\" href=\"/styles/component_#{index}.css\">\n"
        code += "</head>\n"
        code += "<body>\n"
        code += "    <div class=\"container\">\n"
        code += "        <header>\n"
        code += "            <h1>Page #{index}</h1>\n"
        code += "            <nav>\n"
        code += "                <a href=\"/\">Home</a>\n"
        code += "                <a href=\"/about\">About</a>\n"
        code += "            </nav>\n"
        code += "        </header>\n"
        code += "        <main>\n"
        code += "            <section class=\"content\">\n"
        code += "                <p>This is the content for page #{index}.</p>\n"
        code += "            </section>\n"
        code += "        </main>\n"
        code += "        <footer>\n"
        code += "            <p>&copy; 2025 GitHub</p>\n"
        code += "        </footer>\n"
        code += "    </div>\n"
        code += "    <script src=\"/scripts/module_#{index}.js\"></script>\n"
        code += "</body>\n"
        code += "</html>\n"
        code
      end

      def self.generate_yaml_code(index, lines)
        code = "# Configuration for service #{index}\n"
        code += "service:\n"
        code += "  name: service_#{index}\n"
        code += "  version: 1.0.0\n"
        code += "  port: #{3000 + index}\n\n"
        code += "database:\n"
        code += "  host: localhost\n"
        code += "  port: 5432\n"
        code += "  name: service_#{index}_db\n"
        code += "  pool: 10\n\n"
        code += "logging:\n"
        code += "  level: info\n"
        code += "  format: json\n"
        code += "  output: stdout\n\n"
        code += "features:\n"
        code += "  - name: feature_a\n"
        code += "    enabled: true\n"
        code += "  - name: feature_b\n"
        code += "    enabled: false\n\n"
        code += "cache:\n"
        code += "  ttl: 3600\n"
        code += "  max_size: 1000\n"
        code
      end

      def self.generate_json_code(index, lines)
        code = "{\n"
        code += "  \"name\": \"config_#{index}\",\n"
        code += "  \"version\": \"1.0.0\",\n"
        code += "  \"description\": \"Configuration file for service #{index}\",\n"
        code += "  \"settings\": {\n"
        code += "    \"enabled\": true,\n"
        code += "    \"timeout\": 5000,\n"
        code += "    \"retries\": 3,\n"
        code += "    \"endpoints\": [\n"
        code += "      \"https://api.example.com/v1\",\n"
        code += "      \"https://api.backup.com/v1\"\n"
        code += "    ]\n"
        code += "  },\n"
        code += "  \"features\": {\n"
        code += "    \"logging\": true,\n"
        code += "    \"metrics\": true,\n"
        code += "    \"tracing\": false\n"
        code += "  },\n"
        code += "  \"metadata\": {\n"
        code += "    \"author\": \"GitHub\",\n"
        code += "    \"created\": \"2025-01-31\",\n"
        code += "    \"tags\": [\"config\", \"service\", \"api\"]\n"
        code += "  }\n"
        code += "}\n"
        code
      end

      def self.generate_markdown_code(index, lines)
        code = "# Guide #{index}\n\n"
        code += "## Introduction\n\n"
        code += "This guide covers the implementation details for feature #{index}.\n\n"
        code += "## Overview\n\n"
        code += "The feature provides the following capabilities:\n\n"
        code += "- Data processing and transformation\n"
        code += "- Event handling and notification\n"
        code += "- State management and persistence\n\n"
        code += "## Usage\n\n"
        code += "```ruby\n"
        code += "# Example usage\n"
        code += "service = Service#{index}.new\n"
        code += "result = service.process(data)\n"
        code += "```\n\n"
        code += "## API Reference\n\n"
        code += "### `process(input)`\n\n"
        code += "Processes the input data and returns the result.\n\n"
        code += "**Parameters:**\n"
        code += "- `input` - The data to process\n\n"
        code += "**Returns:**\n"
        code += "- Processed result\n\n"
        code += "## Configuration\n\n"
        code += "See `config/service_#{index}.yaml` for configuration options.\n"
        code
      end

      private_class_method def self.initial_calculator_file_contents
        <<~RUBY
          # frozen_string_literal: true

          # A simple calculator class for demonstration purposes
          class Calculator
            attr_reader :history, :last_result

            def initialize
              @history = []
              @last_result = 0
            end

            # Basic arithmetic operations
            def add(a, b)
              result = a + b
              record_operation(:add, a, b, result)
              result
            end

            def subtract(a, b)
              result = a - b
              record_operation(:subtract, a, b, result)
              result
            end

            def multiply(a, b)
              result = a * b
              record_operation(:multiply, a, b, result)
              result
            end

            def divide(a, b)
              raise ArgumentError, "Cannot divide by zero" if b.zero?

              result = a.to_f / b
              record_operation(:divide, a, b, result)
              result
            end

            # Advanced operations
            def power(base, exponent)
              result = base**exponent
              record_operation(:power, base, exponent, result)
              result
            end

            def square_root(number)
              raise ArgumentError, "Cannot calculate square root of negative number" if number < 0

              result = Math.sqrt(number)
              record_operation(:square_root, number, nil, result)
              result
            end

            def percentage(number, percent)
              result = (number * percent) / 100.0
              record_operation(:percentage, number, percent, result)
              result
            end

            # Memory operations
            def clear_history
              @history.clear
              @last_result = 0
            end

            def recall_last
              @last_result
            end

            def get_history(limit = nil)
              return @history if limit.nil?

              @history.last(limit)
            end

            # Chain operations using last result
            def chain_add(value)
              add(@last_result, value)
            end

            def chain_subtract(value)
              subtract(@last_result, value)
            end

            def chain_multiply(value)
              multiply(@last_result, value)
            end

            def chain_divide(value)
              divide(@last_result, value)
            end

            # Statistical operations on history
            def average_of_results
              return 0 if @history.empty?

              sum = @history.sum { |entry| entry[:result] }
              sum.to_f / @history.length
            end

            def max_result
              return nil if @history.empty?

              @history.max_by { |entry| entry[:result] }[:result]
            end

            def min_result
              return nil if @history.empty?

              @history.min_by { |entry| entry[:result] }[:result]
            end

            # Utility methods
            def to_s
              "Calculator(last_result: \#{@last_result}, operations: \#{@history.length})"
            end

            def inspect
              "#<Calculator:0x\#{object_id.to_s(16)} @last_result=\#{@last_result} @history=[\#{@history.length} operations]>"
            end

            private

            def record_operation(operation, operand1, operand2, result)
              @history << {
                operation: operation,
                operand1: operand1,
                operand2: operand2,
                result: result,
                timestamp: Time.now
              }
              @last_result = result
            end
          end
        RUBY
      end

      private_class_method def self.edited_calculator_file_contents
        <<~RUBY
          # frozen_string_literal: true

          # A simple calculator class for demonstration purposes
          class Calculator
            attr_reader :history, :last_result

            def initialize
              @history = []
              @last_result = 0
            end

            # Basic arithmetic operations
            def add(a, b)
              result = a + b
              record_operation(:add, a, b, result)
              result
            end

            def subtract(a, b)
              result = a - b
              record_operation(:subtract, a, b, result)
              result
            end

            def multiply(a, b)
              result = a * b
              record_operation(:multiply, a, b, result)
              result
            end

            def divide(a, b, c)
              raise unless c == 0

              result = a.to_f / b
              record_operation(:divide, a, b, result)
              result
            end

            # Advanced operations
            def power(base, exponent)
              result = base**exponent
              record_operation(:power, base, exponent, result)
              result
            end

            def square_root(number)
              raise ArgumentError, "Cannot calculate square root of negative number" if number < 0

              result = Math.sqrt(number)
              record_operation(:square_root, number, nil, result)
              result
            end

            def percentage(number, percent)
              result = (number * percent) / 100.0
              record_operation(:percentage, number, percent, result)
              result
            end

            # Memory operations
            def clear_history
              @history.clear
              @last_result = 0
            end

            def recall_last_result
              @last_result
            end

            def get_history(limit = nil)
              return @history if limit.nil?

              @history.last(limit)
            end

            # Chain operations using last result
            def chain_add(value)
              add(@last_result, value)
            end

            def chain_subtract(value)
              subtract(@last_result, value)
            end

            def chain_multiply(value)
              multiply(@last_result, value)
            end

            def chain_divide(value)
              divide(@last_result, value)
            end

            # Statistical operations on history
            def average_of_results
              return 0 if @history.empty?

              sum = @history.sum { |entry| entry[:result] }
              sum.to_f / @history.length
            end

            def max_result
              return nil if @history.empty?

              @history.max_by { |entry| entry[:result] }[:result]
            end

            # Utility methods
            def to_s
              "Calculator(last_result: \#{@last_result}, operations: \#{@history.length}) 🫠"
            end

            def inspect
              "#<Calculator:0x\#{object_id.to_s(16)} @last_result=\#{@last_result} @history=[\#{@history.length} operations]>"
            end

            private

            def record_operation(operation, operand1, operand2, result)
              @history << {
                operation: operation,
                operand1: operand1,
                operand2: operand2,
                result: result,
                timestamp: Time.now
              }
              @last_result = result
            end
          end
        RUBY
      end
    end
  end
end
