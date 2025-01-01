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
        - When -large_prs flag is used, creates 11 additional PRs per repo with stress testing characteristics:
          - One with 2000 diff lines spread between files
          - One with 6001 diff lines spread between files
          - One with 3000 diff lines
          - One with 1100 files
          - One with 275 files changed and 50 review threads
          - One with 50 review threads
          - One with multiple file types (.js, .cpp, .sh, .css, .go, .java, .rb, .py, .xml, .yaml, .txt, .mdx)
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
        total_number_of_prs = create_large_prs ? 36 : 14  # 14 regular + 22 large (14 stress + 8 limit-case)
        number_of_draft_prs = options[:num_drafts] || DEFAULT_NUM_DRAFTS
        # Create array of booleans we can pass one-by-one into PR create :draft option
        draft_prs = Array.new(total_number_of_prs) { |i| i < number_of_draft_prs }.shuffle
        given_number_of_commits = total_number_of_commits = (options[:num_commits] || Seeds::Objects::Commit::DEFAULT_NUM_RANDOM_COMMITS)
        number_of_comments = options[:num_comments] || DEFAULT_NUM_COMMENTS
        comment_outside_the_diff = options[:comment_outside_the_diff] || false
        num_files_changed = options[:num_files_changed] || DEFAULT_NUM_FILES_CHANGED

        # Loop through each repo, create PRs in each
        [user_repo, org_repo].each do |repo|
          prs_per_repo = create_large_prs ? 18 : 7  # 7 regular + 7 stress + 4 limit-case when large_prs enabled
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

            puts "\t\tSeeding pull request with 3000 diff lines..."
            seed_3000_diff_lines_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding pull request with 1100 files..."
            seed_1100_files_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding pull request with 275 files and 50 comments..."
            seed_275_files_45_comments_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, possible_commenter_ids: possible_commenter_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding pull request with 50 review threads..."
            seed_50_review_threads_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, possible_commenter_ids: possible_commenter_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"

            puts "\t\tSeeding pull request with multiple file types..."
            seed_multiple_file_types_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"
          end

          if comment_outside_the_diff
            puts "\t\tSeeding pull request with comments outside the diff..."
            seed_comments_outside_the_diff_pr(repo: repo, author: author, reviewer_user_ids: reviewer_user_ids, possible_commenter_ids: possible_commenter_ids, draft: draft_prs.shift)
            puts "\t\tDone!\n"
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

        puts "\nDone!"
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
          repository: pull.repository,
          review:,
          submit_review: true,
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
          # JavaScript files
          changes.add("src/app.js", "// JavaScript application\nconst app = require('express')();\napp.listen(3000);")
          changes.add("src/utils.js", "// Utility functions\nmodule.exports = { helper: () => {} };")
          changes.add("existing.js", "// Modified JavaScript\nconsole.log('hello world');\nfunction main() {}")

          # C++ files
          changes.add("src/main.cpp", "#include <iostream>\nint main() {\n  std::cout << \"Hello World\" << std::endl;\n  return 0;\n}")
          changes.add("include/utils.h", "#ifndef UTILS_H\n#define UTILS_H\nvoid helper();\n#endif")

          # Shell scripts
          changes.add("scripts/build.sh", "#!/bin/bash\necho \"Building project...\"\nmake clean && make")
          changes.add("scripts/deploy.sh", "#!/bin/bash\necho \"Deploying...\"\nscp -r build/ server:/var/www/")

          # CSS files
          changes.add("styles/main.css", ".container {\n  max-width: 1200px;\n  margin: 0 auto;\n}")
          changes.add("styles/components.css", ".button {\n  background: blue;\n  color: white;\n  padding: 10px;\n}")

          # Go files
          changes.add("cmd/main.go", "package main\n\nimport \"fmt\"\n\nfunc main() {\n  fmt.Println(\"Hello, Go!\")\n}")
          changes.add("pkg/utils.go", "package pkg\n\nfunc Helper() string {\n  return \"helper\"\n}")

          # Java files
          changes.add("src/Main.java", "public class Main {\n  public static void main(String[] args) {\n    System.out.println(\"Hello, Java!\");\n  }\n}")
          changes.add("src/Utils.java", "public class Utils {\n  public static void helper() {}\n}")

          # Ruby files
          changes.add("lib/main.rb", "# frozen_string_literal: true\n\nclass Main\n  def self.run\n    puts 'Hello, Ruby!'\n  end\nend")
          changes.add("lib/utils.rb", "# frozen_string_literal: true\n\nmodule Utils\n  def self.helper\n    # helper method\n  end\nend")

          # Python files
          changes.add("src/main.py", "#!/usr/bin/env python3\n\ndef main():\n    print('Hello, Python!')\n\nif __name__ == '__main__':\n    main()")
          changes.add("src/utils.py", "\"\"\"Utility functions\"\"\"\n\ndef helper():\n    pass")

          # XML files
          changes.add("config/settings.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<settings>\n  <database>\n    <host>localhost</host>\n  </database>\n</settings>")
          changes.add("data/sample.xml", "<?xml version=\"1.0\"?>\n<data>\n  <item id=\"1\">Sample</item>\n</data>")

          # YAML files
          changes.add("config/database.yaml", "development:\n  adapter: postgresql\n  database: myapp_dev\n  host: localhost")
          changes.add(".github/workflows/ci.yaml", "name: CI\non: [push]\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v2")

          # Text files
          changes.add("docs/notes.txt", "Project Notes\n=============\n\n- Feature A implemented\n- Bug fixes in module B")
          changes.add("LICENSE.txt", "MIT License\n\nCopyright (c) 2025\n\nPermission is hereby granted...")

          # MDX files
          changes.add("docs/guide.mdx", "# User Guide\n\nimport { CodeBlock } from '../components/CodeBlock'\n\n<CodeBlock language=\"javascript\">\nconsole.log('Hello')\n</CodeBlock>")
          changes.add("blog/post.mdx", "---\ntitle: New Features\ndate: 2025-01-31\n---\n\n# New Features\n\nWe're excited to announce...")
        end

        puts "\t\tOpening PR with multiple file types..."
        ::PullRequest.create_for!(
          repo,
          user: author,
          title: "Pull request with multiple file types",
          body: "This pull request demonstrates various file types: .js, .cpp, .sh, .css, .go, .java, .rb, .py, .xml, .yaml, .txt, .mdx",
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
    end
  end
end
