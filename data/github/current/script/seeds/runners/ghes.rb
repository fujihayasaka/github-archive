# frozen_string_literal: true

require_relative "../runner"
require "json"
require "ruby-progressbar"

# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

# This runner is used to seed test datasets for GHES.
# It is not used for seeding production data and will only run in the enterprise runtime.
module Seeds
  class Runner
    class Ghes < Seeds::Runner
      def self.help
        <<~HELP
        Seed data to a GHES instance for testing.

        Can be called with a size parameter to seed a small, medium, or large dataset. Default is small.

        Dataset sizes can be overridden with the config parameter. For example, to seed 10 users and 5 organizations:
        `ghes --config='{"users": 10, "organizations": 5}'`

        Use the print_config parameter to print the final configuration and return without seeding.
        HELP
      end

      def self.run(options = {})
        # Set our runtime options and configuration
        self.set_options(options)

        # Exit if only printing the configuration
        return if @print_config

        @admin_user = User.find_by(login: "ghe-admin") || Seeds::Objects::User.monalisa
        puts "Admin user: #{@admin_user.login}" if @debug
        raise "Admin user not found" unless @admin_user

        puts "Seeding GHES data..."

        # Create a GitHub App for check runs
        gh_app_name = "ghes-seed-app"
        puts "Finding or creating app '#{gh_app_name}'..." if @debug
        @gh_app = Integration.find_by(name: gh_app_name)
        if !@gh_app.present?
          integration_attributes = {
            owner: @admin_user,
            name: gh_app_name,
            url: "https://example.com",
            visibility: :public_visibility,
          }
          @gh_app = Integration.create!(integration_attributes)
        end

        # Create organizations
        @all_org_ids = []
        progressbar = self.create_progressbar("Organizations", @organizations)
        (0...@organizations).each do |i|
          app = Faker::App.name
          app = app.downcase.gsub(" ", "-")
          # TODO(elee): catch specific error when creating orgs and print friendly error message
          org = Seeds::Objects::Organization.create(
            login: "#{app}-#{i}",
            admin: @admin_user,
            plan: nil,
          )
          @all_org_ids.push(org.id)
          self.increment_progressbar(progressbar)
          puts "Created organization: #{org.login}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create users
        @all_user_ids = []
        progressbar = self.create_progressbar("Users", @users)
        (0...@users).each do |i|
          handle = Faker::Movies::Hackers.handle
          handle = handle.downcase.gsub(" ", "-")
          user = Seeds::Objects::User.create(
            login: "#{handle}-#{i}",
            password: "passworD1", # The default password environment variable is not set in GHES instances
            billing_attempts: nil, # Override the default set for dotcom user seeding
            plan: nil, # Override the default set for dotcom user seeding
          )
          @all_user_ids.push(user.id)
          self.increment_progressbar(progressbar)
          puts "Created user: #{user.login}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create teams on random organizations
        @all_team_ids = []
        progressbar = self.create_progressbar("Teams", @teams)
        (0...@teams).each do
          org = self.random_organization
          team = Seeds::Objects::Team.create!(org: org)
          @all_team_ids.push(team.id)
          self.increment_progressbar(progressbar)
          puts "Created team #{team.name} in #{org.login}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create roles on random organizations
        # We only do this in the enterprise context because
        # repository roles are not available without an Enterprise account in dotcom.
        if GitHub.enterprise?
          progressbar = self.create_progressbar("Roles", @roles)
          (0...@roles).each do
            role = Seeds::Objects::Role.create(owner: self.random_organization)
            self.increment_progressbar(progressbar)
            puts "Created role #{role.name} for #{role.owner.login}" if @debug
          end
          self.finish_progressbar(progressbar)
        end

        # Create repositories on random owners
        @all_repository_ids = []
        progressbar = self.create_progressbar("Repositories", @repositories)
        (0...@repositories).each do |i|
          fake = Faker::Hacker
          name = "#{fake.adjective}-#{fake.noun}-#{i}".gsub(" ", "-")
          owner = [self.random_organization, self.random_user].sample
          repo = Seeds::Objects::Repository.create(
            owner_name: owner.login,
            repo_name: name,
            setup_master: true,
            is_public: false,
          )
          @all_repository_ids.push(repo.id)
          puts "Created repository: #{repo.full_name}" if @debug

          # Install the GitHub App on the repository
          @gh_app.install_on(
            owner,
            repositories: [repo],
            installer: owner.organization? ? @admin_user : owner,
            entry_point: :seeds_runners_actions_create_and_install_github_app
          )
          self.increment_progressbar(progressbar)
        end
        self.finish_progressbar(progressbar)

        # Create issues on random repositories
        @all_issue_ids = []
        progressbar = self.create_progressbar("Issues", @issues)
        (0...@issues).each do
          repo = self.random_repository
          issue = Seeds::Objects::Issue.create(
            repo: repo,
            actor: repo.owner.organization? ? @admin_user : repo.owner,
          )
          @all_issue_ids.push(issue.id)
          self.increment_progressbar(progressbar)
          puts "Created issue: #{issue.number}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create issue comments on random issues
        progressbar = self.create_progressbar("Issue comments", @issue_comments)
        (0...@issue_comments).each do
          issue = self.random_issue
          comment = Seeds::Objects::IssueComment.create(
            issue: issue,
            user: issue.owner,
          )
          self.increment_progressbar(progressbar)
          puts "Created comment: #{comment.body}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create oauth_applications
        progressbar = self.create_progressbar("Oauth applications", @oauth_applications)
        (0...@oauth_applications).each do
          # Temporarily suppress the output of the oauth application creation.
          # The underlying function has a `puts` statement that is redundant/noisy.
          original_stdout = $stdout
          $stdout = File.open(File::NULL, "w")
          oauth_app = Seeds::Objects::OauthApplication.create(owner: self.random_organization)
          $stdout = original_stdout
          self.increment_progressbar(progressbar)
          puts "Created oauth application #{oauth_app.name}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create gists
        @all_gist_ids = []
        progressbar = self.create_progressbar("Gists", @gists)
        (0...@gists).each do
          fake = Faker::Lorem
          gist = Seeds::Objects::Gist.create(
            user: self.random_user,
            contents: [{ name: "#{fake.word}.md", value: fake.sentence }],
          )
          @all_gist_ids.push(gist.id)
          self.increment_progressbar(progressbar)
          puts "Created gist: #{gist.id}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create gist comments
        progressbar = self.create_progressbar("Gist comments", @gist_comments)
        (0...@gist_comments).each do
          gist = self.random_gist
          fake = Faker::Lorem
          comment = Seeds::Objects::GistComment.create(user: gist.owner, gist: gist, body: fake.sentence)
          self.increment_progressbar(progressbar)
          puts "Created gist comment: #{comment.body}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create commits
        progressbar = self.create_progressbar("Commits", @commits)
        (0...@commits).each do
          repo = self.random_repository
          fake = Faker::Lorem
          commit = Seeds::Objects::Commit.create(
            repo: repo,
            message: fake.sentence,
            committer: repo.owner.organization? ? @admin_user : repo.owner,
          )
          self.increment_progressbar(progressbar)
          puts "Created commit: #{commit.oid}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create commit comments
        progressbar = self.create_progressbar("Commit comments", @commit_comments)
        (0...@commit_comments).each do
          repo = self.random_repository
          commit_comment = Seeds::Objects::CommitComment.create(
            user: repo.owner.organization? ? @admin_user : repo.owner,
            repo: repo,
          )
          self.increment_progressbar(progressbar)
          puts "Created commit comment: #{commit_comment.id}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create labels
        progressbar = self.create_progressbar("Labels", @labels)
        (0...@labels).each do |i|
          fake = Faker::Adjective.negative
          label = Seeds::Objects::Label.create(repo: self.random_repository, name: "#{fake}-label-#{i}")
          self.increment_progressbar(progressbar)
          puts "Created label: #{label.name}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create refs
        progressbar = self.create_progressbar("Refs", @refs)
        (0...@refs).each do |i|
          repo = self.random_repository
          ref = Seeds::Objects::Git::Ref.find_or_create_branch_ref(
            repo: repo,
            ref_name: "branch-#{i}",
            target_ref_name: repo.default_branch
          )
          self.increment_progressbar(progressbar)
          puts "Created ref: #{ref.name}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create releases
        progressbar = self.create_progressbar("Releases", @releases)
        (0...@releases).each do |i|
          repo = self.random_repository
          owner = repo.owner.organization? ? @admin_user : repo.owner
          release = Seeds::Objects::Release.create(repo: repo, tag_name: "v1.0." + i.to_s, release_author: owner)
          puts "Created release: #{release.tag_name}" if @debug

          # Create a release asset on each release
          asset = Seeds::Objects::Release.create_asset(release)
          self.increment_progressbar(progressbar)
          puts "Created release asset: #{asset.name}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create milestones
        progressbar = self.create_progressbar("Milestones", @milestones)
        (0...@milestones).each do
          repo = self.random_repository
          Seeds::Objects::Milestone.create(
            created_by: repo.owner.organization? ? @admin_user : repo.owner,
            repository: repo,
          )
          self.increment_progressbar(progressbar)
          puts "Created milestones for #{repo.full_name}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Add repository rulesets
        progressbar = self.create_progressbar("Repository rulesets", @repository_rulesets)
        (0...@repository_rulesets).each do |i|
          repo = self.random_repository
          ruleset = Seeds::Objects::Ruleset.create(source: repo, name: "foo #{i}")
          self.increment_progressbar(progressbar)
          puts "Created repository ruleset #{ruleset.name} for #{repo.full_name}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Add deployments
        progressbar = self.create_progressbar("Deployments", @deployments)
        (0...@deployments).each do
          repo = self.random_repository
          deployment = Seeds::Objects::Deployment.create(
            repository: repo,
            head_sha: repo.commit_for_ref(repo.default_branch).oid,
            integration: @gh_app,
          )
          self.increment_progressbar(progressbar)
          puts "Created deployment: #{deployment.id}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Add repository advisories
        progressbar = self.create_progressbar("Repository advisories", @repository_advisories)
        (0...@repository_advisories).each do
          repo = self.random_repository
          actor = repo.owner.organization? ? @admin_user : repo.owner
          Seeds::Objects::RepositoryAdvisory.create(user: actor, repo: repo)
          self.increment_progressbar(progressbar)
          puts "Created repository advisories for #{repo.full_name}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Add statuses to the default branch
        progressbar = self.create_progressbar("Statuses", @statuses)
        (0...@statuses).each do
          repo = self.random_repository
          status = Seeds::Objects::Status.create(
            repo: repo,
            sha: repo.commit_for_ref(repo.default_branch).oid,
            state: [:success, :error, :failure, :pending].sample,
          )
          self.increment_progressbar(progressbar)
          puts "Created status: #{status.state}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Add pull requests
        @all_pull_request_ids = []
        progressbar = self.create_progressbar("Pull requests", @pull_requests)
        (0...@pull_requests).each do
          repo = self.random_repository
          pr = Seeds::Objects::PullRequest.create(
            repo: repo,
            committer: repo.owner.organization? ? @admin_user : repo.owner,
          )
          @all_pull_request_ids.push(pr.id)
          self.increment_progressbar(progressbar)
          puts "Created pull request: #{pr.number}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Add pull request reviews
        # This currently only supports creating "pending" reviews so that comments can be added afterwards.
        # Pull requests cannot be reviewed by the owner, so we need to create a reviewer
        @all_pull_request_review_ids = []
        reviewer = Seeds::Objects::User.create(
          login: "pr-reviewer",
          password: "passworD1",
          billing_attempts: nil, # Override the default set for dotcom user seeding
          plan: nil, # Override the default set for dotcom user seeding
        )
        progressbar = self.create_progressbar("Pull request reviews", @pull_request_reviews)
        (0...@pull_request_reviews).each do
          pr = self.random_pull_request
          review = Seeds::Objects::PullRequestReview.create(pull_request: pr, user: reviewer, state: :pending)
          @all_pull_request_review_ids.push(review.id)
          self.increment_progressbar(progressbar)
          puts "Pull request review created with id: #{review.id}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Add pull request review comments
        progressbar = self.create_progressbar("Pull request review comments", @pull_request_review_comments)
        (0...@pull_request_review_comments).each do
          review = self.random_pull_request_review
          comment = Seeds::Objects::PullRequestReviewComment.create(user: reviewer, pull_request_review: review)
          self.increment_progressbar(progressbar)
          puts "Created pull request review comment: #{comment.body}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create Memex projects
        @all_memex_project_ids = []
        progressbar = self.create_progressbar("Memex projects", @memex_projects)
        (0...@memex_projects).each do
          memex_project = Seeds::Objects::MemexProject.create(owner: self.random_organization, creator: @admin_user)
          # Add all default workflows to every Memex project
          Seeds::Objects::MemexProjectWorkflow.add_all_default_workflows(memex_project: memex_project, creator: @admin_user)
          @all_memex_project_ids.push(memex_project.id)
          self.increment_progressbar(progressbar)
        end
        self.finish_progressbar(progressbar)

        # Create text columns on random projects
        progressbar = self.create_progressbar("Memex project columns", @memex_project_columns)
        (0...@memex_project_columns).each do |i|
          memex_project = self.random_memex_project
          Seeds::Objects::MemexProjectColumn.create_text_column(
            creator: @admin_user,
            memex_project: memex_project,
            name: "#{Faker::Lorem.unique.word}-#{i}"
          )
          self.increment_progressbar(progressbar)
        end
        self.finish_progressbar(progressbar)

        # Create items on random projects
        progressbar = self.create_progressbar("Memex project items", @memex_project_items)
        (0...@memex_project_items).each do
          is_draft = [true, false].sample
          memex_project = self.random_memex_project
          if is_draft
            Seeds::Objects::MemexProjectItem.create_draft_issue(creator: @admin_user, memex_project: memex_project)
          else
            Seeds::Objects::MemexProjectItem.create_issue_or_pull(
              creator: @admin_user,
              issue_or_pull: [self.random_issue, self.random_pull_request].sample,
              memex_project: memex_project
            )
          end
          self.increment_progressbar(progressbar)
        end
        self.finish_progressbar(progressbar)

        # Create issue links
        progressbar = self.create_progressbar("Issue links", @issue_links)
        (0...@issue_links).each do
          # If less than 2 issues have been created, create a new issue for linking
          if @issues < 2
            issue = Seeds::Objects::Issue.create(
              repo: self.random_repository,
              actor: self.random_repository.owner.organization? ? @admin_user : self.random_repository.owner,
            )
            @all_issue_ids.push(issue.id)
            puts "Created issue for linking: #{issue.number}" if @debug
          end

          issue = self.random_issue
          target_issue = self.random_issue

          # We cannot link an issue to itself
          while target_issue.id == issue.id do
            target_issue = self.random_issue
          end

          repo = issue.repository
          issue_link = Seeds::Objects::IssueLink.create(
            current_issue: issue,
            target_issue: target_issue,
            repo: repo,
            actor: repo.owner.organization? ? @admin_user : repo.owner,
          )
          self.increment_progressbar(progressbar)
          puts "Created issue link: #{issue_link.source_issue.number} -> #{issue_link.target_issue.number}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create issue types
        progressbar = self.create_progressbar("Issue types", @issue_types)
        (0...@issue_types).each do
          issue_type = Seeds::Objects::IssueType.create(
            owner: self.random_organization,
            name: Faker::Lorem.word,
            description: Faker::Lorem.sentence,
            color: [:green, :red, :blue, :yellow].sample,
          )
          self.increment_progressbar(progressbar)
          puts "Created issue type: #{issue_type.name}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create discussions
        progressbar = self.create_progressbar("Discussions", @discussions)
        (0...@discussions).each do
          repo = self.random_repository
          repo.turn_on_discussions(actor: repo.owner, instrument: false)
          discussion = Seeds::Objects::Discussion.create(
            user: repo.owner.organization? ? @admin_user : repo.owner,
            repo: repo,
          )
          self.increment_progressbar(progressbar)
          puts "Created discussion: #{discussion.id}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create discussion posts
        progressbar = self.create_progressbar("Discussion posts", @discussion_posts)
        (0...@discussion_posts).each do
          discussion_post = Seeds::Objects::DiscussionPost.create(
            user: @admin_user,
            team: self.random_team,
          )
          self.increment_progressbar(progressbar)
          puts "Created discussion post: #{discussion_post.id}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create check suites
        @all_check_suite_ids = []
        progressbar = self.create_progressbar("Check suites", @check_suites)
        (0...@check_suites).each do
          repo = self.random_repository
          check_suite = Seeds::Objects::CheckSuite.create(
            repo: repo,
            app: @gh_app,
            head_branch: repo.refs.first.name,
            head_sha: repo.refs.first.sha,
            push: nil,
            attrs: nil
          )
          @all_check_suite_ids.push(check_suite.id)
          self.increment_progressbar(progressbar)
          puts "Created check suite: #{check_suite.id}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create check runs on random check suites
        @all_check_run_ids = []
        progressbar = self.create_progressbar("Check runs", @check_runs)
        (0...@check_runs).each do |i|
          check_suite = self.random_check_suite
          check_run = Seeds::Objects::CheckRun.create(
            check_suite,
            name: "Check run #{i}",
            status: "completed",
            completed_at: Time.now,
            conclusion: "success",
            started_at: Time.now - 1.hour,
            details_url: "https://example.com",
            with_steps: true,
            repository: check_suite.repository,
          )
          @all_check_run_ids.push(check_run.id)
          self.increment_progressbar(progressbar)
          puts "Created check run: #{check_run.id}" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create check annotations
        progressbar = self.create_progressbar("Check annotations", @check_annotations)
        (0...@check_annotations).each do
          check_annotations = Seeds::Objects::CheckAnnotation.create_examples_for_check_run(
            self.random_check_run,
          )
          self.increment_progressbar(progressbar)
          puts "Created #{check_annotations.length} check annotations" if @debug
        end
        self.finish_progressbar(progressbar)

        # Create pushes
        # Note: pushes are failing to create and are disabled for now
        (0...0).each do
          repo = self.random_repository
          push = Seeds::Objects::Push.create(
            **{
              committer: @admin_user,
              repo: repo,
              branch_name: repo.default_branch,
              files: { "README.md" =>
                Faker::Markdown.sandwich(sentences: 15) + Faker::Lorem.paragraphs(number: 4 + rand(3)).join("\n\n") },
              message: "Add #{repo.default_branch}/README.md",
            })
          puts "Created push: #{push.oid}" if @debug
        end

        puts "GHES data seeded successfully!"
      end

      # Helpers for displaying progress
      def self.create_progressbar(obj, total)
        return nil if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

        ProgressBar.create(
          title: obj,
          total: total,
          format: "%a %e | %c/%C | %P% | %t",
        )
      end

      def self.increment_progressbar(progressbar)
        return if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        progressbar.increment
      end

      def self.finish_progressbar(progressbar)
        return if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        progressbar.finish
      end

      # The self.random_* methods are used to get a random object of the given type.
      # We rely on the `find_each` method to handle batched requests of items to keep our memory usage low.
      # See: https://api.rubyonrails.org/classes/ActiveRecord/Batches.html#method-i-find_each

      def self.random_organization
        raise "No organizations created yet" if @all_org_ids.blank?

        begin
          @orgs_enum.peek
        rescue NameError, StopIteration
          @orgs_enum = ::Organization.where(id: @all_org_ids).order("RAND()").find_each
        end

        @orgs_enum.next
      end

      def self.random_user
        raise "No users created yet" if @all_user_ids.blank?

        begin
          @users_enum.peek
        rescue NameError, StopIteration
          @users_enum = ::User.where(id: @all_user_ids).order("RAND()").find_each
        end

        @users_enum.next
      end

      def self.random_repository
        raise "No repositories created yet" if @all_repository_ids.blank?

        begin
          @repos_enum.peek
        rescue NameError, StopIteration
          @repos_enum = ::Repository.where(id: @all_repository_ids).order("RAND()").find_each
        end

        @repos_enum.next
      end

      def self.random_gist
        raise "No gists created yet" if @all_gist_ids.blank?

        begin
          @gists_enum.peek
        rescue NameError, StopIteration
          @gists_enum = ::Gist.where(id: @all_gist_ids).order("RAND()").find_each
        end

        @gists_enum.next
      end

      def self.random_team
        raise "No teams created yet" if @all_team_ids.blank?

        begin
          @teams_enum.peek
        rescue NameError, StopIteration
          @teams_enum = ::Team.where(id: @all_team_ids).order("RAND()").find_each
        end

        @teams_enum.next
      end

      def self.random_issue
        raise "No issues created yet" if @all_issue_ids.blank?

        begin
          @issues_enum.peek
        rescue NameError, StopIteration
          @issues_enum = ::Issue.where(id: @all_issue_ids).order("RAND()").find_each
        end

        @issues_enum.next
      end

      def self.random_memex_project
        raise "No memex projects created yet" if @all_memex_project_ids.blank?

        begin
          @memex_projects_enum.peek
        rescue NameError, StopIteration
          @memex_projects_enum = ::MemexProject.where(id: @all_memex_project_ids).order("RAND()").find_each
        end

        @memex_projects_enum.next
      end

      def self.random_pull_request
        raise "No pull requests created yet" if @all_pull_request_ids.blank?

        begin
          @pull_requests_enum.peek
        rescue NameError, StopIteration
          @pull_requests_enum = ::PullRequest.where(id: @all_pull_request_ids).order("RAND()").find_each
        end

        @pull_requests_enum.next
      end

      def self.random_pull_request_review
        raise "No pull request reviews created yet" if @all_pull_request_review_ids.blank?

        begin
          @pull_request_reviews_enum.peek
        rescue NameError, StopIteration
          @pull_request_reviews_enum = ::PullRequestReview.where(id: @all_pull_request_review_ids).order("RAND()").find_each
        end

        @pull_request_reviews_enum.next
      end

      def self.random_check_suite
        raise "No check suites created yet" if @all_check_suite_ids.blank?

        begin
          @check_suites_enum.peek
        rescue NameError, StopIteration
          @check_suites_enum = ::CheckSuite.where(id: @all_check_suite_ids).order("RAND()").find_each
        end

        @check_suites_enum.next
      end

      def self.random_check_run
        raise "No check runs created yet" if @all_check_run_ids.blank?

        begin
          @check_runs_enum.peek
        rescue NameError, StopIteration
          @check_runs_enum = ::CheckRun.where(id: @all_check_run_ids).order("RAND()").find_each
        end

        @check_runs_enum.next
      end

      def self.set_options(options)
        @debug = options[:debug] || false
        @size = options[:size] || "small"
        @config = options[:config] || {}
        @print_config = options[:print_config] || false

        puts "Debug mode enabled" if @debug
        puts "Using size: #{@size}"

        # Set the default options for the size
        case @size
        when "small"
          self.set_small_options
        when "medium"
          self.set_medium_options
        when "large"
          self.set_large_options
        else
          raise "Invalid size: #{@size}"
        end

        # Override the default options with any provided in the config
        if options[:config].present?
          config = JSON.parse(options[:config], symbolize_names: true)
          config.each do |key, value|
            instance_variable_set("@#{key}", value)
          end
        end

        # Print the configuration
        puts "Configuration:"
        instance_variables.each do |var|
          puts "  #{var[1..-1]}: #{instance_variable_get(var).inspect}" if ![:@debug, :@size, :@config, :@print_config].include?(var)
        end
      end

      def self.set_small_options
        @organizations = 1
        @users = 1
        @teams = 1
        @repositories = 1
        @repository_advisories = 1
        @repository_rulesets = 1
        @roles = 1
        @labels = 1
        @statuses = 1
        @issues = 1
        @pull_requests = 1
        @issue_comments = 1
        @pull_request_reviews = 1
        @pull_request_review_comments = 1
        @refs = 1
        @releases = 1
        @gists = 1
        @gist_comments = 1
        @memex_projects = 1
        @memex_project_columns = 1
        @memex_project_items = 1
        @milestones = 1
        @oauth_applications = 1
        @issue_links = 1
        @issue_types = 1
        @check_annotations = 1
        @check_runs = 1
        @check_suites = 1
        @commits = 1
        @commit_comments = 1
        @deployments = 1
        @discussions = 1
        @discussion_posts = 1
        @pushes = 1
      end

      def self.set_medium_options
        @organizations = 10
        @users = 50
        @teams = 10
        @repositories = 150
        @repository_advisories = 1
        @repository_rulesets = 1
        @roles = 1
        @labels = 300
        @statuses = 5
        @issues = 300
        @pull_requests = 300
        @issue_comments = 1
        @pull_request_reviews = 1
        @pull_request_review_comments = 1
        @refs = 50
        @releases = 1
        @gists = 50
        @gist_comments = 50
        @memex_projects = 10
        @memex_project_columns = 1
        @memex_project_items = 1
        @milestones = 1
        @oauth_applications = 10
        @issue_links = 1
        @issue_types = 1
        @check_annotations = 1
        @check_runs = 100
        @check_suites = 10
        @commits = 100
        @commit_comments = 5
        @deployments = 1
        @discussions = 10
        @discussion_posts = 10
        @pushes = 50
      end

      def self.set_large_options
        @organizations = 5000
        @users = 25000
        @teams = 10000
        @repositories = 75000
        @repository_advisories = 100
        @repository_rulesets = 20000
        @roles = 1000
        @labels = 150000
        @statuses = 2
        @issues = 150000
        @pull_requests = 150000
        @issue_comments = 1
        @pull_request_reviews = 1
        @pull_request_review_comments = 1
        @refs = 100000
        @releases = 1
        @gists = 25000
        @gist_comments = 25000
        @memex_projects = 1
        @memex_project_columns = 1
        @memex_project_items = 1
        @milestones = 1
        @oauth_applications = 1000
        @issue_links = 1
        @issue_types = 1
        @check_annotations = 1
        @check_runs = 100000
        @check_suites = 100000
        @commits = 100000
        @commit_comments = 10000
        @deployments = 1
        @discussions = 25000
        @discussion_posts = 10000
        @pushes = 100000
      end
    end
  end
end
