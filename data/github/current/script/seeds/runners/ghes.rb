# typed: true
# frozen_string_literal: true

require_relative "../runner"

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

        It is possible to run the runner in parallel. Each type of data is forked into explicitly specificed processes parameter.
        Beware that some of the data may not be created due to collisions such as same name or commit to the same HEAD.

        Please bear in mind that the parallel processes will require additional memory and CPU resources, especially for the large data set.

        The large data set creates thousands of messages in aqueduct and can take a long time to complete. It requires increasing redis' maxmemory.
        Please monitor your instance during the seeding.

        Can be called with a size parameter to seed a small, medium, or large dataset. Default is small.

        Dataset sizes can be overridden with the config parameter, the rest will be set to the respective size's default.
        For example, to seed 10 users and 5 organizations:

        `ghes --config='{"users": 10, "organizations": 5}'`
        Example on how to run the GHES seed for only specified types of data:

        `ghes --config_override='{"memex_project_columns": 20}'`

        Use the print_config parameter to print the final configuration and return without seeding.

        -------------------------


        Use the print data types parameter to print the allowed data types and return without seeding.
        The data types are:

          - base_data (organizations, users, teams, roles)

          - repository_data (repositories, labels, refs, releases, repository_rulesets, repository_advisories, deployments)

          - code_review_data (commits, commit_comments, statuses, pushes, pull_requests, pull_request_reviews, pull_request_comments, check_suites, check_runs, check_annotations)

          - issue_data (issues, issue_comments, issue_links, issue_types, milestones)

          - memex_project_data (memex_projects, memex_project_columns, memex_project_items)

          - gist_data (gists, gist_comments)

          - discussion_data (discussions, discussion_posts)

          - misc_data (oauth_applications)

        HELP
      end

      @data_types = Set[
        "base_data",
        "repository_data",
        "code_review_data",
        "issue_data",
        "memex_project_data",
        "gist_data",
        "discussion_data",
        "misc_data"
      ]

      def self.print_data_types
        puts "Allowed subsets of data types are: "
        @data_types.each do |dt|
          puts "\t - #{dt}"
        end
      end

      def self.run(options = {})
        require "parallel"
        require "json"
        setup_environment(options)
        return print_data_types if @print_data_types
        # Exit if only printing the configuration
        return if @print_config

        # TODO: (Adam)
        # - add checks if any data exists in self.random_* methods
        # - The RAND() order functions could be a bit risky in terms of performance when we use this on a large dataset
        puts "Seeding GHES data..."
        if @data_type.nil?
          create_base_data
          create_repository_data
          create_code_review_data
          create_issue_data
          create_memex_project_data
          create_gist_data
          create_discussion_data
          create_misc_data
        else
          run_data_type
        end
        reset_enumerations
        puts "GHES data seeded successfully!"
      end

      def self.reset_enumerations
        @users_enum = nil
        @orgs_enum = nil
        @repos_enum = nil
        @teams_enum = nil
        @issues_enum = nil
        @gists_enum = nil
        @memex_projects_enum = nil
        @pull_requests_enum = nil
        @pull_request_reviews_enum = nil
        @check_suites_enum = nil
        @check_runs_enum = nil
      end

      def self.run_data_type
        case @data_type
        when "base_data"
          create_base_data
        when "repository_data"
          create_repository_data
        when "code_review_data"
          create_code_review_data
        when "issue_data"
          create_issue_data
        when "memex_project_data"
          create_memex_project_data
        when "gist_data"
          create_gist_data
        when "discussion_data"
          create_discussion_data
        when "misc_data"
          create_misc_data
        else raise "Unsupported data_type provided - #{@data_type}"
        end
      end

      # Helper for displaying progress bar via the Parallel library
      def self.create_progressbar_opts(title, total)
        return if Rails.env.test? || @debug # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        {
          title: title,
          total: total,
          format: "%a %e | %c/%C | %P% | %t",
          output: $stdout
        }
      end

      # The self.random_* methods are used to get a random object of the given type.
      # We rely on the `find_each` method to handle batched requests of items to keep our memory usage low.
      # See: https://api.rubyonrails.org/classes/ActiveRecord/Batches.html#method-i-find_each

      def self.random_organization
        begin
          @orgs_enum.peek
        rescue NameError, StopIteration
          @orgs_enum = ::Organization
            .order(Arel.sql("RAND()")).find_each(batch_size: 200)
        end
        @orgs_enum.next
      end

      def self.random_user
        begin
          @users_enum.peek
        rescue NameError, StopIteration
          @users_enum = ::User
          .where(type: "User")
          .has_verified_email
          .order(Arel.sql("RAND()"))
          .find_each(batch_size: 200)
        end
        @users_enum.next
      end

      def self.random_repository
        begin
          @repos_enum.peek
        rescue NameError, StopIteration
          @repos_enum = ::Repository
          .order(Arel.sql("RAND()"))
          .find_each(batch_size: 200)
        end
        @repos_enum.next
      end

      def self.random_gist
        begin
          @gists_enum.peek
        rescue NameError, StopIteration
          @gists_enum = ::Gist.order(Arel.sql("RAND()")).find_each(batch_size: 200)
        end
        @gists_enum.next
      end

      def self.random_team
        begin
          @teams_enum.peek
        rescue NameError, StopIteration
          @teams_enum = ::Team
          .order(Arel.sql("RAND()")).find_each(batch_size: 200)
        end
        @teams_enum.next
      end

      def self.random_issue
        begin
          @issues_enum.peek
        rescue NameError, StopIteration
          @issues_enum = ::Issue
          .order(Arel.sql("RAND()")).find_each(batch_size: 200)
        end
        @issues_enum.next
      end

      def self.random_memex_project
        begin
          @memex_projects_enum.peek
        rescue NameError, StopIteration
          @memex_projects_enum = ::MemexProject.order(Arel.sql("RAND()")).find_each(batch_size: 200)
        end
        @memex_projects_enum.next
      end

      def self.random_pull_request
        begin
          @pull_requests_enum.peek
        rescue NameError, StopIteration
          @pull_requests_enum = ::PullRequest.order(Arel.sql("RAND()")).find_each(batch_size: 200)
        end
        @pull_requests_enum.next
      end

      def self.random_pull_request_review
        begin
          @pull_request_reviews_enum.peek
        rescue NameError, StopIteration
          @pull_request_reviews_enum = ::PullRequestReview.order(Arel.sql("RAND()")).find_each(batch_size: 200)
        end
        @pull_request_reviews_enum.next
      end

      def self.random_check_suite
        begin
          @check_suites_enum.peek
        rescue NameError, StopIteration
          @check_suites_enum = ::CheckSuite.order(Arel.sql("RAND()")).find_each(batch_size: 200)
        end
        @check_suites_enum.next
      end

      def self.random_check_run
        begin
          @check_runs_enum.peek
        rescue NameError, StopIteration
          @check_runs_enum = ::CheckRun.order(Arel.sql("RAND()")).find_each(batch_size: 200)
        end
        @check_runs_enum.next
      end

      def self.setup_environment(options)
        # Set our runtime options and configuration
        set_options(options)
        @admin_user = find_or_create_admin_user
        puts "Admin user: #{@admin_user.login}" if @debug
        raise "Admin user not found" unless @admin_user
        @reviewer = create_reviewer
      end

      def self.find_or_create_admin_user
        User.find_by(login: "ghe-admin") || Seeds::Objects::User.monalisa
      end

      def self.create_gh_app_for_check_runs
        gh_app_name = "ghes-seed-app"
        puts "Finding or creating app '#{gh_app_name}'..." if @debug
        @gh_app = Integration.find_by(name: gh_app_name)
        if !@gh_app.present?
          integration_attributes = {
            owner: @admin_user,
            name: gh_app_name,
            url: "https://example.com",
            visibility: "public_visibility",
          }
          @gh_app = Integration.create!(integration_attributes)
        end
      end

      # creates organizations, users, teams and (if enterprise) roles
      def self.create_base_data
        create_organizations
        create_users
        create_teams
        create_roles if GitHub.enterprise?
      end

      def self.create_repository_data
        create_gh_app_for_check_runs
        create_repositories
        create_labels
        create_refs
        create_releases
        create_repository_rulesets
        create_repository_advisories
        create_deployments
      end

      def self.create_issue_data
        create_issues
        create_issue_comments
        create_issue_links
        create_issue_types
        create_milestones
      end

      def self.create_code_review_data
        create_gh_app_for_check_runs
        create_commits
        create_commit_comments
        create_statuses
        create_pushes
        create_pull_requests
        create_pull_request_reviews
        create_pull_request_comments
        create_check_suites
        create_check_runs
        create_check_annotations
      end

      def self.create_memex_project_data
        create_memex_projects
        create_memex_project_columns
        create_memex_project_items
      end

      def self.create_misc_data
        create_oauth_applications
      end

      def self.create_gist_data
        create_gists
        create_gist_comments
      end

      def self.create_discussion_data
        create_discussions
        create_discussion_posts
      end

      sig { params(operation_name: String, retries: Integer, block: T.proc.returns(T.untyped)).returns(T.untyped) }
      def self.with_retries(operation_name, retries: @retries, &block)
        tries = 0
        begin
          tries += 1 # This could also be in ensure block but we don't want to retry immediately on enqueue err
          block.call
        rescue ActiveJob::EnqueueFailedError, Redis::CommandError => e
          if tries <= retries
            puts "[Process-#{Parallel.worker_number}] Got an enqueue error, going to backoff - #{e.message}" if @debug
            exponential_backoff(tries)
            retry
          end
          puts "[Process-#{Parallel.worker_number}] Failed #{operation_name} after #{tries} attempts - #{e.message}" if @debug
        rescue Seeds::Objects::CreateFailed, ActiveRecord::RecordInvalid,
           Git::Ref::ComparisonMismatch, ActiveRecord::RecordNotUnique => e
          if tries <= retries
            puts "Retrying #{operation_name} (#{tries}/#{retries}) due to #{e.message}" if @debug
            retry
          end
          puts "Failed #{operation_name} after #{tries} attempts - #{e.message}" if @debug
        rescue => e
          if e.backtrace.nil?
            puts "Unknown error in #{operation_name} - #{e.message}" if @debug
          else
            puts "Unknown error in #{operation_name} - #{e.message}\n#{e.backtrace&.join("\n\t")}" if @debug
          end
        end
      end

      sig { params(tries: Integer).void }
      def self.exponential_backoff(tries)
        exponent = 3
        interval = 3
        backoff = (exponent**tries) * interval # 1st retry - 9 seconds # 2nd - 27 # 3rd - 81 seconds
        puts "[Process-#{Parallel.worker_number}] Exponential backoff sleep for #{backoff}"
        sleep(backoff)
      end

      def self.create_organizations
        return if @organizations.zero?
        processes = get_number_of_processes(@organizations)
        progressbar_opts = self.create_progressbar_opts("Organizations", @organizations)
        created_ok = Parallel.map(0...@organizations, progress: progressbar_opts, in_processes: processes) do |i|
          app = Faker::App.name
          app = app.downcase.gsub(" ", "-")
          with_retries("creating organization") do
            org = Seeds::Objects::Organization.create(
              login: "#{app}-#{i}",
              admin: @admin_user,
              plan: nil,
            )
            puts "[Process-#{Parallel.worker_number}] Created organization: #{org.login}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@organizations} orgs"
      end

      def self.create_users
        return if @users.zero?
        processes = get_number_of_processes(@users)
        progressbar_opts = self.create_progressbar_opts("Users", @users)
        created_ok = Parallel.map(0...@users, progress: progressbar_opts, in_processes: processes) do |i|
          handle = T.let(Faker::Movies::Hackers.handle, String)
          handle = handle.downcase.gsub(" ", "-")
          with_retries("creating_user") do
            user = Seeds::Objects::User.create(
              login: "#{handle}-#{i}",
              password: "passworD1", # The default password environment variable is not set in GHES instances
              billing_attempts: nil, # Override the default set for dotcom user seeding
              plan: nil, # Override the default set for dotcom user seeding
            )
            puts "[Process-#{Parallel.worker_number}] Created user: #{user.login}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@users} users"
      end

      def self.create_teams
        return if @teams.zero?
        raise "Cannot create teams without organizations" unless has_any_orgs?
        processes = get_number_of_processes(@teams)
        progressbar_opts = self.create_progressbar_opts("Teams", @teams)
        created_ok = Parallel.map(0...@teams, progress: progressbar_opts, in_processes: processes) do
          org = random_organization
          with_retries("creating teams") do
            team = Seeds::Objects::Team.create!(org: org)
            raise "Failed to create team for #{org.login}" unless team
            puts "[Process-#{Parallel.worker_number}] Created team #{team.name} in #{org.login}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@teams} teams"
      end

      # We only do this in the enterprise context because
      # repository roles are not available without an Enterprise account in dotcom.
      def self.create_roles
        return if @roles.zero?
        raise "Cannot create roles without organizations" unless has_any_orgs?
        processes = get_number_of_processes(@roles)
        progressbar_opts = create_progressbar_opts("Roles", @roles)
        created_roles = Parallel.map(0...@roles, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating roles") do
            role = Seeds::Objects::Role.create(org: random_organization)
            puts "[Process-#{Parallel.worker_number}] Created role #{role.name} for #{role.owner.login}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_roles}/#{@roles} roles"
      end

      def self.create_repositories
        return if @repositories.zero?
        raise "Cannot create repositories without organizations or users" unless has_any_orgs? || has_any_users?
        processes = get_number_of_processes(@repositories)
        progressbar_opts = create_progressbar_opts("Repositories", @repositories)
        created_ok = Parallel.map(0...@repositories, progress: progressbar_opts, in_processes: processes) do |i|
          fake = Faker::Hacker
          name = "#{fake.adjective}-#{fake.noun}-#{i}".gsub(" ", "-")
          with_retries("creating repositories") do
            owner = [random_organization, random_user].sample
            repo = Seeds::Objects::Repository.create(
              owner_name: owner.login,
              repo_name: name,
              setup_master: true,
              is_public: false
            )
            puts "[Process-#{Parallel.worker_number}] Created repository: #{repo.full_name}" if @debug
            # Install the GitHub App on the repository
            @gh_app.install_on(
              owner,
              repositories: [repo],
              installer: owner.organization? ? @admin_user : owner,
              entry_point: :seeds_runners_actions_create_and_install_github_app
            )
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@repositories} respositories"
      end

      def self.create_labels
        return if @labels.zero?
        raise "Cannot create labels without repositories" unless has_any_repos?
        processes = get_number_of_processes(@labels)
        progressbar_opts = create_progressbar_opts("Labels", @labels)
        created_ok = Parallel.map(0...@labels, progress: progressbar_opts, in_processes: processes) do |i|
          fake = Faker::Adjective.negative
          with_retries("creating labels") do
            label = Seeds::Objects::Label.create(repo: random_repository, name: "#{fake}-label-#{i}")
            puts "[Process-#{Parallel.worker_number}] Created label: #{label.name}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@labels} labels."
      end

      def self.create_refs
        return if @refs.zero?
        raise "Cannot create refs without repositories" unless has_any_repos?
        processes = get_number_of_processes(@refs)
        progressbar_opts = self.create_progressbar_opts("Refs", @refs)
        created_ok = Parallel.map(0...@refs, progress: progressbar_opts, in_processes: processes) do |i|
          with_retries("creating refs") do
            repo = self.random_repository
            puts "[Process-#{Parallel.worker_number}] [Thread-#{Parallel.worker_number}] Creating ref for repo (#{repo.name})branch #{repo.default_branch}" if @debug
            random_name = Faker::Esport.player
            ref = Seeds::Objects::Git::Ref.find_or_create_branch_ref(
              repo: repo,
              ref_name: "#{random_name}-branch-#{i}",
              target_ref_name: repo.default_branch
            )
            puts "[Process-#{Parallel.worker_number}] Created ref: #{ref.name}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@refs} refs"
      end

      def self.create_releases
        return if @releases.zero?
        raise "Cannot create releases without repositories" unless has_any_repos?
        processes = get_number_of_processes(@releases)
        progressbar_opts = self.create_progressbar_opts("Releases", @releases)
        created_ok = Parallel.map(0...@releases, progress: progressbar_opts, in_processes: processes) do |i|
          with_retries("creating releases") do
            repo = self.random_repository
            owner = repo.owner.organization? ? @admin_user : repo.owner
            release = Seeds::Objects::Release.create(repo: repo, tag_name: "v1.0." + i.to_s, release_author: owner)
            puts "[Process-#{Parallel.worker_number}] Created release: #{release.tag_name}" if @debug

            # Create a release asset on each release
            asset = Seeds::Objects::Release.create_asset(release)
            puts "[Process-#{Parallel.worker_number}] Created release asset: #{asset.name}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@releases} releases"
      end

      def self.create_repository_rulesets
        return if @repository_rulesets.zero?
        raise "Cannot create repository rulesets without repositories" unless has_any_repos?
        processes = get_number_of_processes(@repository_rulesets)
        progressbar_opts = self.create_progressbar_opts("Repository rulesets", @repository_rulesets)
        created_repo_rulesets = Parallel.map(0...@repository_rulesets, progress: progressbar_opts, in_processes: processes) do |i|
          with_retries("creating repository rulesets") do
            repo = self.random_repository
            ruleset = Seeds::Objects::Ruleset.create(source: repo, name: "foo #{Parallel.worker_number}_#{i}")
            puts "[Process-#{Parallel.worker_number}] Created repository ruleset #{ruleset.name} for #{repo.full_name}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_repo_rulesets}/#{@repository_rulesets} repository rulesets"
      end

      def self.create_repository_advisories
        return if @repository_advisories.zero?
        raise "Cannot create repository advisories without repositories" unless has_any_repos?
        processes = get_number_of_processes(@repository_advisories)
        progressbar_opts = self.create_progressbar_opts("Repository advisories", @repository_advisories)
        created_ok = Parallel.map(0...@repository_advisories, progress: progressbar_opts, in_processes: processes) do
          repo = self.random_repository
          actor = repo.owner.organization? ? @admin_user : repo.owner
          with_retries("creating repository advisory") do
            Seeds::Objects::RepositoryAdvisory.create(user: actor, repo: repo)
            puts "[Process-#{Parallel.worker_number}] Created repository advisories for #{repo.full_name}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@repository_advisories} repository advisories"
      end

      def self.create_deployments
        return if @deployments.zero?
        raise "Cannot create deployments without repositories" unless has_any_repos?
        processes = get_number_of_processes(@deployments)
        progressbar_opts = self.create_progressbar_opts("Deployments", @deployments)
        created_ok = Parallel.map(0...@deployments, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating deployment") do
            repo = random_repository
            deployment = Seeds::Objects::Deployment.create(
              repository: repo,
              head_sha: repo.commit_for_ref(repo.default_branch).oid,
              integration: @gh_app,
            )
            puts "[Process-#{Parallel.worker_number}] Created deployment: #{deployment.id}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@deployments} deployments"
      end

      def self.create_issues
        return if @issues.zero?
        raise "Cannot create issues without repositories" unless has_any_repos?
        processes = get_number_of_processes(@issues)
        progressbar_opts = create_progressbar_opts("Issues", @issues)
        created_ok = Parallel.map(0...@issues, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating issues") do
            repo = random_repository
            issue = Seeds::Objects::Issue.create(
              repo: repo,
              actor: repo.owner.organization? ? @admin_user : repo.owner,
            )
            puts "[Process-#{Parallel.worker_number}] Created issue: #{issue.number}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@issues} issues"
      end

      def self.create_issue_comments
        raise "Cannot create issue comments without issues" unless has_any_issues?
        return if @issue_comments.zero?
        processes = get_number_of_processes(@issue_comments)
        progressbar_opts = create_progressbar_opts("Issue comments", @issue_comments)
        created_issue_comments = Parallel.map(0...@issue_comments, progress: progressbar_opts, in_processes: processes) do
          with_retries("create issues comment") do
            issue = random_issue
            comment = Seeds::Objects::IssueComment.create(
              issue: issue,
              user: issue.owner, #random_user,
            )
            puts "[Process-#{Parallel.worker_number}] Created comment: #{comment.body}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_issue_comments}/#{@issue_comments} issue comments."
      end

      def self.create_issue_links
        return if @issue_links.zero?
        raise "Cannot create issue links without issues" unless has_any_issues?
        raise "Cannot create issue link because there aren't more than 1 issue" if ::Issue.count < 2
        processes = get_number_of_processes(@issue_links)
        progressbar_opts = self.create_progressbar_opts("Issue links", @issue_links)
        created_ok = Parallel.map(0...@issue_links, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating issue link") do
            issue = random_issue
            target_issue = random_issue

            # We cannot link an issue to itself
            while target_issue.id == issue.id do
              target_issue = random_issue
            end

            repo = issue.repository
            issue_link = Seeds::Objects::IssueLink.create(
              current_issue: issue,
              target_issue: target_issue,
              repo: repo,
              actor: repo.owner.organization? ? @admin_user : repo.owner,
            )
            puts "[Process-#{Parallel.worker_number}] Created issue link: #{issue_link.source_issue.number} -> #{issue_link.target_issue.number}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@issue_links} issue links."
      end

      def self.create_issue_types
        return if @issue_types.zero?
        raise "Cannot create issue types without organizations" unless has_any_orgs?
        processes = get_number_of_processes(@issue_types)
        progressbar_opts = self.create_progressbar_opts("Issue types", @issue_types)
        created_ok = Parallel.map(0...@issue_types, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating issue type") do
            issue_type = Seeds::Objects::IssueType.create(
              owner: random_organization,
              name: Faker::Lorem.word,
              description: Faker::Lorem.sentence,
              color: [:green, :red, :blue, :yellow].sample,
            )
            puts "[Process-#{Parallel.worker_number}] Created issue type: #{issue_type.name}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@issue_types} issue types."
      end

      def self.create_milestones
        return if @milestones.zero?
        raise "Cannot create milestones without repositories" unless has_any_repos?
        processes = get_number_of_processes(@milestones)
        progressbar_opts = create_progressbar_opts("Milestones", @milestones)
        created_milestones = Parallel.map(0...@milestones, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating milestone")  do
            repo = random_repository
            Seeds::Objects::Milestone.create(
              created_by: repo.owner.organization? ? @admin_user : repo.owner,
              repository: repo,
            )
            puts "[Process-#{Parallel.worker_number}] Created milestones for #{repo.full_name}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_milestones}/#{@milestones} milestones."
      end

      def self.create_commits
        return if @commits.zero?
        raise "Cannot create commits without repositories" unless has_any_repos?
        progressbar_opts = create_progressbar_opts("Commits", @commits)
        processes = get_number_of_processes(@commits)
        # We have to run this in parallel, otherwise commits to the same repo will be out of sync.
        created_commits = Parallel.map(0...@commits, progress: progressbar_opts, in_processes: processes) do
          fake = Faker::Lorem
          with_retries("creating commit") do
            repo = random_repository
            commit = Seeds::Objects::Commit.create(
              repo: repo,
              message: fake.sentence,
              committer: repo.owner.organization? ? @admin_user : repo.owner
            )
            puts "[Process-#{Parallel.worker_number}] Created commit: #{commit.oid}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_commits}/#{@commits} commits"
      end

      def self.create_commit_comments
        return if @commit_comments.zero?
        raise "Cannot create commit comments without repositories" unless has_any_repos?
        processes = get_number_of_processes(@commit_comments)
        progressbar_opts = create_progressbar_opts("Commit comments", @commit_comments)
        created_ok = Parallel.map(0...@commit_comments, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating commit comment") do
            repo = random_repository
            commit_comment = Seeds::Objects::CommitComment.create(
              user: repo.owner.organization? ? @admin_user : repo.owner,
              repo: repo,
            )
            puts "[Process-#{Parallel.worker_number}] Created commit comment: #{commit_comment.id}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@commit_comments} commit comments"
      end

      # Add statuses to the default branch
      def self.create_statuses
        return if @statuses.zero?
        raise "Cannot create statuses without repositories" unless has_any_repos?
        processes = get_number_of_processes(@statuses)
        progressbar_opts = create_progressbar_opts("Statuses", @statuses)
        created_ok = Parallel.map(0...@statuses, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating status") do
            repo = random_repository
            status = Seeds::Objects::Status.create(
              repo: repo,
              sha: repo.commit_for_ref(repo.default_branch).oid,
              state: [:success, :error, :failure, :pending].sample,
            )
            puts "[Process-#{Parallel.worker_number}] Created status: #{status.state}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@statuses} statuses"
      end

      # Note: pushes are failing to create and are disabled for now
      def self.create_pushes
        return if @pushes.zero?
        puts " Note: pushes are failing to create and are disabled for now"
        raise "Cannot create pushses without repositories" unless has_any_repos?
        processes = get_number_of_processes(@pushes)
        progressbar_opts = create_progressbar_opts("Pushes", @pushes)
        created_ok = Parallel.map(0...0, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating push") do
            repo = random_repository
            push = Seeds::Objects::Push.create(
              **{
                committer: @admin_user,
                repo: repo,
                branch_name: repo.default_branch,
                files: { "README.md" =>
                  Faker::Markdown.sandwich(sentences: 15) + Faker::Lorem.paragraphs(number: 4 + rand(3)).join("\n\n") },
                message: "Add #{repo.default_branch}/README.md",
              })
            puts "[Process-#{Parallel.worker_number}] Created push: #{push.oid}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@pushes} pushes"
      end

      def self.create_pull_requests
        return if @pull_requests.zero?
        raise "Cannot create pull requests without repositories" unless has_any_repos?
        processes = get_number_of_processes(@pull_requests)
        progressbar_opts = create_progressbar_opts("Pull requests", @pull_requests)
        created_ok = Parallel.map(0...@pull_requests, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating pull request") do
            repo = random_repository
            pr = Seeds::Objects::PullRequest.create(
              repo: repo,
              committer: repo.owner.organization? ? @admin_user : repo.owner,
            )
            puts "[Process-#{Parallel.worker_number}] Created pull request: #{pr.number}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@pull_requests} pull requests."
      end

      # Pull requests cannot be reviewed by the owner, so we need to create a reviewer
      def self.create_reviewer
        Seeds::Objects::User.create(
          login: "pr-reviewer",
          password: "passworD1",
          billing_attempts: nil, # Override the default set for dotcom user seeding
          plan: nil, # Override the default set for dotcom user seeding
        )
      end

      # This currently only supports creating "pending" reviews so that comments can be added afterwards.
      def self.create_pull_request_reviews
        return if @pull_request_reviews.zero?
        raise "Cannot create pull request reviews without pull requests" unless has_any_pull_requests?
        processes = get_number_of_processes(@pull_request_reviews)
        progressbar_opts = self.create_progressbar_opts("Pull request reviews", @pull_request_reviews)
        created_ok = Parallel.map(0...@pull_request_reviews, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating pull request review") do
            pr = self.random_pull_request
            review = Seeds::Objects::PullRequestReview.create(pull_request: pr, user: @reviewer, state: :pending)
            puts "[Process-#{Parallel.worker_number}] Pull request review created with id: #{review.id}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@pull_request_reviews} pull requests reviews."
      end

      def self.create_pull_request_comments
        return if @pull_request_review_comments.zero?
        raise "Cannot create pull request comments without pull request reviews" unless has_any_pull_request_reviews?
        processes = get_number_of_processes(@pull_request_review_comments)
        progressbar_opts = self.create_progressbar_opts("Pull request review comments", @pull_request_review_comments)
        created_ok = Parallel.map(0...@pull_request_review_comments, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating pull request review comment") do
            review = self.random_pull_request_review
            comment = Seeds::Objects::PullRequestReviewComment.create(user: @reviewer, pull_request_review: review)
            puts "[Process-#{Parallel.worker_number}] Created pull request review comment: #{comment.body}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@pull_request_review_comments} PR review comments"
      end

      def self.create_check_suites
        return if @check_suites.zero?
        raise "Cannot create check suites without repositories" unless has_any_repos?
        processes = get_number_of_processes(@check_suites)
        progressbar_opts = create_progressbar_opts("Check suites", @check_suites)
        created_ok = Parallel.map(0...@check_suites, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating check suite") do
            repo = random_repository
            check_suite = Seeds::Objects::CheckSuite.create(
              repo: repo,
              app: @gh_app,
              head_branch: repo.refs.first.name,
              head_sha: repo.refs.first.sha,
              push: nil,
              attrs: nil
            )
            puts "[Process-#{Parallel.worker_number}] Created check suite: #{check_suite.id}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@check_suites} check suites"
      end

      # Creates check runs on random check suites
      def self.create_check_runs
        return if @check_runs.zero?
        raise "Cannot create check runs without check suites" unless has_any_check_suites?
        processes = get_number_of_processes(@check_runs)
        progressbar_opts = self.create_progressbar_opts("Check runs", @check_runs)
        created_ok = Parallel.map(0...@check_runs, progress: progressbar_opts, in_processes: processes) do |i|
          with_retries("creating check run") do
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
            puts "[Process-#{Parallel.worker_number}] Created check run: #{check_run.id}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@check_runs} check runs"
      end

      def self.create_check_annotations
        return if @check_annotations.zero?
        raise "Cannot create check annotations without check runs" unless has_any_check_runs?
        processes = get_number_of_processes(@check_annotations)
        progressbar_opts = create_progressbar_opts("Check annotations", @check_annotations)
        created_ok = Parallel.map(0...@check_annotations, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating check annotation") do
            check_annotations = Seeds::Objects::CheckAnnotation.create_examples_for_check_run(
              random_check_run,
            )
            puts "[Process-#{Parallel.worker_number}] Created #{check_annotations.length} check annotations" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@check_annotations} check annotations."
      end

      def self.create_memex_projects
        return if @memex_projects.zero?
        raise "Cannot create memex projects without organizations" unless has_any_orgs?
        processes = get_number_of_processes(@memex_projects)
        progressbar_opts = create_progressbar_opts("Memex projects", @memex_projects)
        created_ok = Parallel.map(0...@memex_projects, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating memex project") do
            memex_project = Seeds::Objects::MemexProject.create(owner: random_organization, creator: @admin_user)
            # Add all default workflows to every Memex project
            Seeds::Objects::MemexProjectWorkflow.add_all_default_workflows(memex_project: memex_project, creator: @admin_user)
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@memex_projects} memex projects."
      end

      # Create text columns on random projects
      def self.create_memex_project_columns
        return if @memex_project_columns.zero?
        raise "Cannot create memex project columns without memex projects" unless has_any_memex_projects?
        processes = get_number_of_processes(@memex_project_columns)
        progressbar_opts = create_progressbar_opts("Memex project columns", @memex_project_columns)
        created_ok = Parallel.map(0...@memex_project_columns, progress: progressbar_opts, in_processes: processes) do |i|
          with_retries("creating memex project column") do
            memex_project = random_memex_project
            col = Seeds::Objects::MemexProjectColumn.create_text_column(
              creator: @admin_user,
              memex_project: memex_project,
              name: "#{Faker::Lorem.unique.word}-#{Parallel.worker_number}-#{i}"
            )
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@memex_project_columns} memex projects columns."
      end

      # Create items on random projects
      def self.create_memex_project_items
        return if @memex_project_items.zero?
        raise "Cannot create memex project items without memex projects" unless has_any_memex_projects?
        processes = get_number_of_processes(@memex_project_items)
        progressbar_opts = create_progressbar_opts("Memex project items", @memex_project_items)
        created_ok = Parallel.map(0...@memex_project_items, progress: progressbar_opts, in_processes: processes) do
          is_draft = [true, false].sample
          with_retries("creating memex project item") do
            memex_project = random_memex_project
            if is_draft
              Seeds::Objects::MemexProjectItem.create_draft_issue(creator: @admin_user, memex_project: memex_project)
            else
              Seeds::Objects::MemexProjectItem.create_issue_or_pull(
                creator: @admin_user,
                issue_or_pull: [self.random_issue, self.random_pull_request].sample,
                memex_project: memex_project
              )
            end
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@memex_project_items} memex projects items."
      end

      def self.create_oauth_applications
        return if @oauth_applications.zero?
        raise "Cannot create oauth applications without organizations" unless has_any_orgs?
        processes = get_number_of_processes(@oauth_applications)
        progressbar_opts = create_progressbar_opts("Oauth applications", @oauth_applications)
        created = Parallel.map(0...@oauth_applications, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating oauth appliction") do
            # Temporarily suppress the output of the oauth application creation.
            # The underlying function has a `puts` statement that is redundant/noisy.
            original_stdout = $stdout
            $stdout = File.open(File::NULL, "w")
            oauth_app = Seeds::Objects::OauthApplication.create(owner: random_organization)
            $stdout = original_stdout
            puts "[Process-#{Parallel.worker_number}] Created oauth application #{oauth_app.name}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created}/#{@oauth_applications} oauth applications."
      end

      def self.create_gists
        return if @gists.zero?
        raise "Cannot create gists without users" unless has_any_users?
        processes = get_number_of_processes(@gists)
        progressbar_opts = self.create_progressbar_opts("Gists", @gists)
        created_ok = Parallel.map(0...@gists, progress: progressbar_opts, in_processes: processes) do
          fake = Faker::Lorem
          with_retries("creating gist") do
            gist = Seeds::Objects::Gist.create(
              user: random_user,
              contents: [{ name: "#{fake.word}.md", value: fake.sentence }],
            )
            puts "[Process-#{Parallel.worker_number}] Created gist: #{gist.id}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@gists} gists"
      end

      def self.create_gist_comments
        return if @gist_comments.zero?
        raise "Cannot create gist comments without gists" unless has_any_gists?
        processes = get_number_of_processes(@gist_comments)
        progressbar_opts = create_progressbar_opts("Gist comments", @gist_comments)
        created_gist_comments = Parallel.map(0...@gist_comments, progress: progressbar_opts, in_processes: processes) do
          fake = Faker::Lorem
          with_retries("creating gist comment") do
            gist = random_gist
            comment = Seeds::Objects::GistComment.create(user: gist.owner, gist: gist, body: fake.sentence)
            puts "[Process-#{Parallel.worker_number}] Created gist comment: #{comment.body}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_gist_comments}/#{@gist_comments} gist comments"
      end

      def self.create_discussions
        return if @discussions.zero?
        raise "Cannot create discussion because there are no repositoroies" unless has_any_repos?
        processes = get_number_of_processes(@discussions)
        progressbar_opts = create_progressbar_opts("Discussions", @discussions)
        created_ok = Parallel.map(0...@discussions, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating discussion") do
            repo = random_repository
            repo.turn_on_discussions(actor: repo.owner, instrument: false)
            discussion = Seeds::Objects::Discussion.create(
              user: can_user_repo_owner(repo) ? @admin_user : repo.owner,
              repo: repo,
            )
            puts "[Process-#{Parallel.worker_number}] Created discussion: #{discussion.id}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_ok}/#{@discussions} discussions"
      end

      def self.can_user_repo_owner(repo)
        repo.owner.organization? || !repo.owner.emails.verified.any?
      end

      def self.create_discussion_posts
        return if @discussion_posts.zero?
        raise "Cannot create discussion posts without teams" unless has_any_teams?
        processes = get_number_of_processes(@discussion_posts)
        progressbar_opts = self.create_progressbar_opts("Discussion posts", @discussion_posts)
        created_discussion_posts = Parallel.map(0...@discussion_posts, progress: progressbar_opts, in_processes: processes) do
          with_retries("creating discussion post") do
            discussion_post = Seeds::Objects::DiscussionPost.create(
              user: @admin_user,
              team: self.random_team,
            )
            puts "[Process-#{Parallel.worker_number}] Created discussion post: #{discussion_post.id}" if @debug
            1
          end
        end.compact.sum
        puts "Created #{created_discussion_posts}/#{@discussion_posts} discussions posts"
      end

      sig { params(set_size: Integer).returns(Integer) }
      def self.get_number_of_processes(set_size)
        set_size < @processes ? set_size : @processes
      end

      sig { returns(T::Boolean) }
      def self.has_any_orgs?
        ::Organization.any?
      end

      sig { returns(T::Boolean) }
      def self.has_any_teams?
        ::Team.any?
      end

      sig { returns(T::Boolean) }
      def self.has_any_pull_requests?
        ::PullRequest.any?
      end

      sig { returns(T::Boolean) }
      def self.has_any_pull_request_reviews?
        ::PullRequestReview.any?
      end

      sig { returns(T::Boolean) }
      def self.has_any_issues?
        ::Issue.any?
      end

      sig { returns(T::Boolean) }
      def self.has_any_users?
        ::User.any?
      end

      sig { returns(T::Boolean) }
      def self.has_any_repos?
        ::Repository.any?
      end
      sig { returns(T::Boolean) }
      def self.has_any_gists?
        ::Gist.any?
      end
      sig { returns(T::Boolean) }
      def self.has_any_memex_projects?
        ::MemexProject.any?
      end
      sig { returns(T::Boolean) }
      def self.has_any_check_runs?
        ::CheckRun.any?
      end
      sig { returns(T::Boolean) }
      def self.has_any_check_suites?
        ::CheckSuite.any?
      end

      def self.set_options(options)
        @debug = options[:debug] || false
        @size = options[:size] || "small"
        @config = options[:config] || {}
        @processes = options[:processes] || 0
        @print_config = options[:print_config] || false
        @print_data_types = options[:print_data_types] || false
        @data_type = options[:data_type] || nil
        @retries = 3

        puts "Debug mode enabled" if @debug
        if @processes.zero?
          puts "Running in a single-threaded manner"
        else
          puts "Using #{@processes} parallel processes (forks)"
        end

        puts "Using size: #{@size}"

        if options[:config_override].present?
          set_empty_options_to_override
          config = JSON.parse(options[:config_override], symbolize_names: true)
          config.each do |key, value|
            instance_variable_set("@#{key}", value)
          end
        else
          # Set the default options for the size
          case @size
          when "small"
            set_small_options
          when "medium"
            set_medium_options
          when "large"
            set_large_options
          else
            raise "Invalid size: #{@size}"
          end

          # This doesn't override the dataset, just adjusts it's values.
          # Override the default options with any provided in the config
          if options[:config].present?
            config = JSON.parse(options[:config], symbolize_names: true)
            config.each do |key, value|
              instance_variable_set("@#{key}", value)
            end
          end
        end

        # Print the configuration
        puts "Configuration:"
        instance_variables.each do |var|
          puts "  #{var[1..-1]}: #{instance_variable_get(var).inspect}" if ![:@debug, :@size, :@config, :@print_config].include?(var)
        end
      end

      def self.set_empty_options_to_override
        @organizations = 0
        @users = 0
        @teams = 0
        @repositories = 0
        @repository_advisories = 0
        @repository_rulesets = 0
        @roles = 0
        @labels = 0
        @statuses = 0
        @issues = 0
        @pull_requests = 0
        @issue_comments = 0
        @pull_request_reviews = 0
        @pull_request_review_comments = 0
        @refs = 0
        @releases = 0
        @gists = 0
        @gist_comments = 0
        @memex_projects = 0
        @memex_project_columns = 0
        @memex_project_items = 0
        @milestones = 0
        @oauth_applications = 0
        @issue_links = 0
        @issue_types = 0
        @check_annotations = 0
        @check_runs = 0
        @check_suites = 0
        @commits = 0
        @commit_comments = 0
        @deployments = 0
        @discussions = 0
        @discussion_posts = 0
        @pushes = 0
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
        @issues = 2 # Create 2 issues so we can link them together
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
        @pull_request_reviews = 20
        @pull_request_review_comments = 20
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
        @issue_links = 1 # Maybe do (@issues / 3).floot # You can't have issue_links >= issues
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
