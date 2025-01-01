# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class IssueDependencies < Seeds::Runner
      BLOCKED_BY_ISSUES_SMALL = 5
      BLOCKED_BY_ISSUES_MEDIUM = 15
      BLOCKED_BY_ISSUES_MAX = 100
      NOT_OWNED_ORG_NAME = "Issue-Deps"

      def self.help
        <<~HELP
        Create sample data for Issues Dependencies
        Parameters of dataset size, pick one of the following:
          --small -> small data set with no cross-org issues
          --medium -> medium data set with cross-org issues (default)
          --full -> add the #{BLOCKED_BY_ISSUES_MAX} limit of blocked by issues and prs
        Other parameters available:
          --seed -> set randomizer seed number
          --verbose -> outputs every generation step
        HELP
      end

      def self.run(options = {})
        require_relative "./check_run"

        prepare_options(options)

        if seed_number > 0
          puts "Using seed '#{seed_number}'"
          srand(seed_number)
        else
          seed = Random.new_seed
          puts "Assigning seed '#{seed}'"
          srand(seed)
        end

        puts "Dataset size #{dataset_size}...#{verbose? ? " (verbose)" : ""}"

        not_owned_org_data = setup_not_owned_org
        return unless not_owned_org_data

        blocked_by_issues = seed_monalisa_repos(not_owned_org_data)

        setup_project_with_issues(issues: blocked_by_issues)

        puts "Repairing Elastometer indexes..."
        Elastomer::App.run ["repair"]
      end

      def self.prepare_options(options)
        options = options.transform_keys(&:to_sym)
        is_verbose = !!options[:verbose]

        seed = options[:seed] || 0

        small = !!options[:small]
        medium = !!options[:medium]
        full = !!options[:full]

        dataset_size = if full
          :full
        elsif medium
          :medium
        elsif small
          :small
        else
          :medium
        end

        @options = { is_verbose:, dataset_size:, seed: }
      end

      def self.verbose?
        @options[:is_verbose]
      end

      def self.dataset_size
        @options[:dataset_size]
      end

      def self.seed_number
        @options[:seed] || 0
      end

      def self.setup_not_owned_org
        if dataset_size == :small
          puts "Small dataset: skipping setup of not-owned Organization..."
          return {}
        end

        sizes = case dataset_size
        when :full
          { users: 5, teams: 3, labels_per_repo: 8, issues_per_repo: 20, pulls_per_repo: 5, max_comments_per_issue: 3, milestones_per_repo: 3 }
        else
          { users: 3, teams: 1, labels_per_repo: 4, issues_per_repo: 5, pulls_per_repo: 1, max_comments_per_issue: 1, milestones_per_repo: 1 }
        end

        org_name = NOT_OWNED_ORG_NAME
        org_login = "#{org_name.downcase}-org"
        org_admin_login = "#{org_name.downcase}-org-admin"

        puts "Setting up not-owned Organization #{org_name}..."

        org = ::Organization.find_by(login: org_login)
        if org.present?
          puts "Org #{org_name} already exists, skipping seed data..."
          return nil
        end

        org_admin = Seeds::Objects::User.create(login: org_admin_login)
        monalisa = Seeds::Objects::User.monalisa

        org = Seeds::Objects::Organization.create(login: org_login, admin: org_admin)
        org_main_team = T.must(::Team.find_by(name: "Employees", organization: org))

        org_users = []
        sizes[:users].times { org_users << Seeds::Objects::User.create(login: Seeds::DataHelper.random_username) }
        add_users_to_team(users: org_users, team: org_main_team)
        org_users << org_admin

        # Add teams
        org_users << org_admin
        team_reviewers = []
        sizes[:teams].times do |i|
          team = T.must(Seeds::Objects::Team.create!(
            org: org,
            name: "#{org_name} #{Faker::Dessert.flavor}-#{i} Reviewers"
          ))
          team_reviewers << team

          users_to_add = org_users.sample(rand(1..org_users.size))
          add_users_to_team(users: users_to_add, team:)
        end

        # Add repositories
        issues_and_prs = {}
        Issue.transaction do
          Label.transaction do
            # no acces repo
            open_org_private_repo = create_repository(owner: org, repo_name: "private-repo", is_public: false)
            open_org_private_repo.add_team(org_main_team, action: :write)
            issues_and_prs[:no_access] = seed_repository(
              repo: open_org_private_repo,
              assignee_set: org_users,
              reviewer_user_set: org_users,
              reviewer_team_set: team_reviewers.sample(rand(1..team_reviewers.size)),
              labels_count: sizes[:labels_per_repo],
              issues_count: sizes[:issues_per_repo],
              pulls_count: sizes[:pulls_per_repo],
              max_comments: sizes[:max_comments_per_issue],
              milestones_count: sizes[:milestones_per_repo],
            )
          end
        end

        Issue.transaction do
          Label.transaction do
            # read access repo
            open_org_public_read_repo = create_repository(owner: org, repo_name: "read-repo", is_public: true)
            open_org_public_read_repo.add_team(org_main_team, action: :write)
            open_org_public_read_repo.add_member(monalisa, action: :read)
            issues_and_prs[:read_access] = seed_repository(
              repo: open_org_public_read_repo,
              assignee_set: [*org_users, monalisa],
              reviewer_user_set: org_users,
              reviewer_team_set: team_reviewers.sample(rand(1..team_reviewers.size)),
              labels_count: sizes[:labels_per_repo],
              issues_count: sizes[:issues_per_repo],
              pulls_count: sizes[:pulls_per_repo],
              max_comments: sizes[:max_comments_per_issue],
              milestones_count: sizes[:milestones_per_repo],
            )
          end
        end

        Issue.transaction do
          Label.transaction do
            # write repo
            open_org_public_write_repo = create_repository(owner: org, repo_name: "write-repo", is_public: true)
            open_org_public_write_repo.add_team(org_main_team, action: :write)
            open_org_public_write_repo.add_member(monalisa, action: :write)
            issues_and_prs[:write_access] = seed_repository(
              repo: open_org_public_write_repo,
              assignee_set: [*org_users, monalisa],
              reviewer_user_set: [*org_users, monalisa],
              reviewer_team_set: team_reviewers.sample(rand(1..team_reviewers.size)),
              labels_count: sizes[:labels_per_repo],
              issues_count: sizes[:issues_per_repo],
              pulls_count: sizes[:pulls_per_repo],
              max_comments: sizes[:max_comments_per_issue],
              milestones_count: sizes[:milestones_per_repo],
              add_issue_templates: true,
            )
          end
        end

        { org:, org_admin:, items: issues_and_prs }
      end

      def self.seed_monalisa_repos(not_owned_org_data)
        monalisa = Seeds::Objects::User.monalisa

        public_repo = T.must(::Repository.find_by(name: "smile", owner_login: monalisa.login))
        private_repo = T.must(::Repository.find_by(name: "illuminati", owner_login: monalisa.login))

        not_owned_org_admin = nil
        if dataset_size != :small
          not_owned_org_admin = not_owned_org_data[:org_admin]
          public_repo.add_member(not_owned_org_admin, action: :write)
          private_repo.add_member(not_owned_org_admin, action: :write)
        end

        sizes = case dataset_size
        when :small
          { issues_count: BLOCKED_BY_ISSUES_SMALL, blocking_count: BLOCKED_BY_ISSUES_SMALL }
        when :full
          { issues_count: BLOCKED_BY_ISSUES_MAX, blocking_count: (BLOCKED_BY_ISSUES_MAX / 2).ceil }
        else
          { issues_count: BLOCKED_BY_ISSUES_MEDIUM, blocking_count: BLOCKED_BY_ISSUES_MEDIUM }
        end => { issues_count:, blocking_count: }

        not_owned_items = not_owned_org_data[:items]
        items = {}
        blocked_by_issues = []
        GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
          Issue.transaction do
            items[:public] = seed_repository(
              repo: public_repo,
              assignee_set: [monalisa, not_owned_org_admin].compact,
              reviewer_user_set: [monalisa, not_owned_org_admin].compact,
              labels_count: 5,
              issues_count:,
              pulls_count: 0,
              max_comments: 1,
              milestones_count: 1,
            )
          end
          Issue.transaction do
            items[:private] = seed_repository(
              repo: private_repo,
              assignee_set: [monalisa, not_owned_org_admin].compact,
              reviewer_user_set: [monalisa, not_owned_org_admin].compact,
              labels_count: 5,
              issues_count:,
              pulls_count: 0,
              max_comments: 1,
              milestones_count: 1,
            )
          end

          # small dataset
          blocked_by_issues_to_create = [{
            issue_title: "Blocked by (single)",
            blocking_issues: items[:public][:issues].sample(1),
          }, {
            issue_title: "Blocked by (small)",
            blocking_issues: items[:public][:issues].sample(BLOCKED_BY_ISSUES_SMALL),
          }, {
            issue_title: "Blocked by cross-repo (single)",
            blocking_issues: items[:private][:issues].sample(1),
          }, {
            issue_title: "Blocked by cross-repo (small)",
            blocking_issues: items[:private][:issues].sample(BLOCKED_BY_ISSUES_SMALL),
          }]

          # medium dataset
          if [:medium, :full].include?(dataset_size)
            not_owned_items = not_owned_org_data[:items]
            issues_per_source = (BLOCKED_BY_ISSUES_MEDIUM / 5).ceil

            blocked_by_issues_to_create.concat([{
              issue_title: "Blocked by (med)",
              blocking_issues: items[:public][:issues].sample(BLOCKED_BY_ISSUES_MEDIUM)
            }, {
              issue_title: "Blocked by cross-repo (med)",
              blocking_issues: items[:private][:issues].sample(BLOCKED_BY_ISSUES_MEDIUM),
            }, {
              issue_title: "Blocked by cross-org (single)",
              blocking_issues: not_owned_items[:no_access][:issues].sample(1),
            }, {
              issue_title: "Blocked by cross-org (small)",
              blocked_by_actor: not_owned_org_admin,
              blocking_issues: [
                not_owned_items[:read_access][:issues].sample,
                not_owned_items[:no_access][:issues].sample,
                not_owned_items[:write_access][:issues].sample,
                items[:private][:issues].sample,
                items[:public][:issues].sample,
              ],
            }, {
              issue_title: "Blocked by cross-org (med)",
              blocked_by_actor: not_owned_org_admin,
              blocking_issues: [
                not_owned_items[:read_access][:issues].sample(issues_per_source),
                not_owned_items[:no_access][:issues].sample(issues_per_source),
                not_owned_items[:write_access][:issues].sample(issues_per_source),
                items[:private][:issues].sample(issues_per_source),
                items[:public][:issues].sample(issues_per_source),
              ].flatten.first(BLOCKED_BY_ISSUES_MEDIUM),
            }])
          end

          # full dataset
          if dataset_size == :full
            not_owned_items = not_owned_org_data[:items]
            issues_per_source = (BLOCKED_BY_ISSUES_MAX / 5).ceil

            blocked_by_issues_to_create.concat([{
              issue_title: "Blocked by (max)",
              blocking_issues: items[:public][:issues].sample(BLOCKED_BY_ISSUES_MAX),
            }, {
              issue_title: "Blocked by cross-repo (max)",
              blocking_issues: items[:private][:issues].sample(BLOCKED_BY_ISSUES_MAX),
            }, {
              issue_title: "Blocked by cross-org (limit)",
              blocked_by_actor: not_owned_org_admin,
              blocking_issues: [
                not_owned_items[:read_access][:issues].sample(issues_per_source),
                not_owned_items[:no_access][:issues].sample(issues_per_source),
                not_owned_items[:write_access][:issues].sample(issues_per_source),
                items[:private][:issues].sample(issues_per_source),
                items[:public][:issues].sample(issues_per_source),
              ].flatten.first(BLOCKED_BY_ISSUES_MAX),
            }])
          end

          blocked_by_issues_to_create.each do |blocked_issue_data|
            blocked_by_issues << add_issue_with_blocked_bys(
              repo: public_repo,
              issue_creator: monalisa,
              **blocked_issue_data
            )
          end

          blocked_by_blocked_by_issues = add_issue_with_blocked_bys(
            repo: public_repo,
            issue_title: "Blocked by blocked-bys",
            issue_creator: monalisa,
            blocking_issues: blocked_by_issues,
            blocked_by_actor: not_owned_org_admin,
          )

          add_issue_blocking_n_issues(
            repo: private_repo,
            blocking_issue: blocked_by_blocked_by_issues,
            total_blocked_issues: blocking_count,
            actor: monalisa,
          )

          blocked_by_issues << blocked_by_blocked_by_issues
        end
      end

      def self.add_issue_with_blocked_bys(repo:, issue_title: nil, issue_creator:, blocking_issues:, blocked_by_actor: nil)
        puts "> adding blocked by issue '#{issue_title}'" if verbose?

        blocked_issue = create_issue(
          repo:,
          title: issue_title,
          actor: issue_creator,
          state: "open",
        )
        blocked_by_actor = issue_creator unless blocked_by_actor.present?
        blocking_issues = [blocking_issues] unless blocking_issues.is_a?(Array)
        blocking_issues.each do |blocking_issue|
          blocked_issue.add_blocked_by!(blocking_issue, blocked_by_actor)
        end

        blocked_issue
      end

      def self.add_issue_blocking_n_issues(repo:, blocking_issue:, total_blocked_issues:, actor: nil)
        puts "> adding issue '#{blocking_issue.title}' as blocker of #{total_blocked_issues} issues" if verbose?

        labels = repo.labels.map(&:name)
        assignees = repo.members

        total_blocked_issues.times do |i|
          labels_count = rand(0..labels.size)
          assignees_count = rand(0..assignees.size)
          blocked_issue = create_issue(
            repo:,
            title: "Blocked by #{blocking_issue.number}-#{i}",
            actor: actor,
            state: "open",
            labels: labels.sample(labels_count),
            assignees: assignees.sample(assignees_count),
          )
          blocked_issue.add_blocked_by!(blocking_issue, actor)
        end
      end

      def self.add_users_to_team(users:, team:)
        users.each do |user|
          team.add_member(user)
        end
      end

      def self.create_repository(owner:, repo_name: nil, is_public: false)
        GH::Context.enabled do
          repo = Seeds::Objects::Repository.create(
            owner_name: owner.login,
            repo_name: repo_name,
            setup_master: true,
            is_public:,
          )
          puts "repo generated => #{GitHub.url}/#{repo.name_with_display_owner}"
          repo
        end
      end

      # Seeds given repository with Issues and PRs.
      #
      # repo - Repository to be seeded
      # assignee_set - Array of Users
      # reviewer_user_set - Array of Users
      # reviewer_team_set - Array of Teams
      # labels_count - number of labels to generate
      # issues_count - number of issues to generate
      # pulls_count - number of PRs to generate
      # max_comments - max number of comments to add to issues and PRs
      # milestones_count  - number of milestone to generate
      #
      # Returns list of Issues and PRs generated for this repo
      def self.seed_repository(
        repo:,
        assignee_set: [],
        reviewer_user_set: [],
        reviewer_team_set: [],
        labels_count: 1,
        issues_count: 1,
        pulls_count: 1,
        max_comments: 0,
        milestones_count: 0,
        add_issue_templates: false
      )
        puts "Setting up repository #{repo.name_with_display_owner}..."
        if verbose?
          puts <<~MSG.squish
            ...with #{issues_count} issues,
            #{pulls_count} pulls,
            #{labels_count} labels,
            #{milestones_count} milestones"
          MSG
        end

        reviewer_team_set.each do |team|
          repo.add_team(team, action: :write)
        end

        labels = repo.labels.map(&:name)
        if labels_count > 0
          puts "> generating labels..." if verbose?
          created_labels = create_labels(labels_count:)
          assign_labels_to_repository(repo: repo, labels: created_labels)
          labels.concat(created_labels.map { |l| l[:name] })
        end

        milestones = []
        puts "> generating milestones..." if milestones_count > 0 && verbose?
        milestones_count.times do |i|
          milestone_title = "Milestone #{i}"

          milestone_exists = Milestone.where(repository_id: repo.id, title: milestone_title).exists?
          next if milestone_exists

          puts ">> creating milestone #{milestone_title}..." if verbose?

          milestones << repo.milestones.create(
            title: milestone_title,
            state: i > 2 ? "closed" : "open",
            created_by: reviewer_user_set.any? ? reviewer_user_set.sample : repo.owner
          )
        end

        issues = []
        prs = []
        GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
          puts "> generating issues..." if issues_count > 0
          issues_count.times do |i|
            actor = assignee_set.any? ? assignee_set.sample : repo.owner

            assignees = assignee_set.sample(rand(0..assignee_set.size))

            issue_labels_count = rand(0..labels.size)

            issue_labels = labels.sample(issue_labels_count)

            number_of_comments = rand(0..max_comments)

            if verbose?
              puts <<~MSG.squish
              >> generating issue #{i + 1}
                with #{number_of_comments} comments,
                #{assignees.count} assignees,
                #{issue_labels.count} labels
              MSG
            end

            state = i <= issues_count * 0.75 ? "open" : "closed"
            state_reason = state == "closed" && rand(0..1).zero? ? "not_planned" : ""

            issues << create_issue(
              repo:,
              actor:,
              state:,
              state_reason:,
              assignees:,
              labels: issue_labels,
              number_of_comments: number_of_comments,
              milestone: milestones.sample,
            )
          end

          puts "> generating PRs..." if pulls_count > 0 && verbose?
          pulls_count.times do |i|
            creator = assignee_set.sample
            assignees = assignee_set.sample(rand(0..2))
            pull_labels = labels.sample(rand(0..5))
            check_run_options = rand(2).zero? ? generate_random_pr_run_check : nil

            # Ensure creator is not assigned as a reviewer
            reviewer_user_ids = reviewer_user_set.sample(rand(0..5)).map(&:id) - [creator.id]
            reviewer_team_ids = reviewer_team_set.sample(rand(0..5)).map(&:id)
            reviewer_ids = reviewer_user_ids + reviewer_team_ids
            review_state = PullRequest.reviewable_states.keys.sample

            number_of_comments = rand(0..max_comments)

            if verbose?
              puts <<~MSG.squish
              >> creating PR #{i + 1} with #{reviewer_ids.count} reviewers, #{number_of_comments} comments,
                #{assignees.count} assignees, #{pull_labels.count}
                labels#{check_run_options.nil? ? "" : ", and check suite"}
              MSG
            end

            prs << create_pull(
              assignees: assignees,
              check_run_options: check_run_options,
              creator: creator,
              labels: pull_labels,
              number_of_comments: number_of_comments,
              repo: repo,
              review_state: review_state,
              reviewer_user_ids: reviewer_user_ids,
              reviewer_team_ids: reviewer_team_ids,
              state: %w[open closed merged].sample,
            )
          end

          # copied from seeds/runners/issues_react:
          #   hack to clear the user contribution cache and make sure it's rebuilt when we run dotcom
          #   so that we see user repositories and don't have an empty repository picker
          #   the key format is taken from packages/hovercards/app/models/user_ranked/cache.rb
          user_id = Seeds::Objects::User.monalisa.id
          since = 1.year.ago.strftime("%m-%Y")
        end

        add_templates_to_repository(repo:) if add_issue_templates

        { issues:, prs: }
      end

      # Returns Array of hashes with label attributes, example:
      #  [
      #    {name: "bug", color: "red"},
      #    {name: "wontfix", color: "black", description: "Known issue, won't fix"}
      #  ]
      def self.create_labels(labels_count:)
        labels = []
        labels_count.times do |i|
          labels << {
            name: "#{generate_label_name}-#{i}",
            color: Faker::Color.hex_color[1..-1],
            description: rand(2) == 0 ? Faker::Hipster.sentence : "",
          }
        end
        labels
      end

      def self.assign_labels_to_repository(repo:, labels:)
        labels.each do |hash|
          repo.labels.create(hash)
        end
        repo.save!
      end

      # Creates Issue with key elements rendered in Hyperlist list item
      #
      # assignees - Array of Users (may include creator)
      # check_run_options - Hash of options used to create a check run
      # creator - User
      # has_checks - Boolean for whether this PR has associated check runs
      # labels - Array of hashes with label attributes
      # number_of_comments - Integer number of comments that will be created on the PR
      # repo - Repository
      # review_state - String value for PullRequest#reviewable_state
      # reviewer_user_ids - Array of User ids (excludes creator)
      # reviewer_team_ids - Array of Team ids
      # state - String value for PullRequest#state
      #
      # Returns PullRequest
      def self.create_issue(
        repo:,
        actor: nil,
        title: nil,
        body: nil,
        assignees: [],
        labels: [],
        state: "open",
        state_reason: "",
        number_of_comments: 0,
        milestone: nil
      )
        title = generate_title unless title.present?
        body = generate_text_content unless body.present?
        actor = repo.owner unless actor.present?

        issue = repo.issues.create(
          user: actor,
          title:,
          body:,
          state: state,
          state_reason: state_reason,
        )

        issue.assignees = assignees if assignees.any?

        if labels.any?
          labels.each do |label|
            l = issue.repository.labels.find_by_name(label)
            issue.labels.push(l) unless l.nil?
          end
        end

        if milestone.present?
          issue.update!(milestone:)
        end

        number_of_comments.times do
          comment_author = assignees.any? ? assignees.sample : actor
          comment_body = generate_text_content(5)
          issue.comments.create(issue:, user: comment_author, body: comment_body)
        end

        issue.save!

        issue
      end

      # Creates PullRequest
      #
      # repo - Repository
      # creator - User
      # state - String value for PullRequest#state
      # review_state - String value for PullRequest#reviewable_state
      # reviewer_user_ids - Array of User ids (excludes creator)
      # reviewer_team_ids - Array of Team ids
      # assignees - Array of Users (may include creator)
      # labels - Array of hashes with label attributes
      # check_run_options - Hash of options used to create a check run
      # number_of_comments - Integer number of comments that will be created on the PR
      #
      # Returns PullRequest
      def self.create_pull(
        repo:,
        creator:,
        state:,
        review_state:,
        reviewer_user_ids:,
        reviewer_team_ids:,
        assignees:,
        labels:,
        check_run_options:,
        number_of_comments:
      )
        pull = Seeds::Objects::PullRequest.create(
          repo: repo,
          base_ref: repo.default_branch_ref,
          committer: creator,
          is_draft: review_state == "draft",
          reviewer_user_ids: reviewer_user_ids,
          reviewer_team_ids: reviewer_team_ids,
          title: generate_title
        )

        pull.reviewable_state = review_state
        pull.save!

        issue = pull.issue

        if assignees.any?
          issue.assignees = assignees
          issue.save!
        end

        if labels.any?
          labels.each do |label|
            label = repo.labels.find_by_name(label)
            issue.labels.push(label) unless label.nil?
          end
          issue.save!
        end

        possible_commenter_ids = [creator.id] | reviewer_user_ids | assignees.map(&:id)

        number_of_comments.times do |_i|
          commenter = User.find(possible_commenter_ids.sample)
          body = generate_text_content
          ::Seeds::Objects::IssueComment.create(issue: issue, user: commenter, body: body)
        end

        if check_run_options.present?
          launch_github_app = GitHub.launch_github_app || setup_launch_github_app_on(repo)

          # NOTE: We are manually creating a check suite here, because the check suite created by
          # Seeds::Runner::CheckRun is associated with the incorrect head sha, and subsequently
          # does not show up in the PR or hyperlist UI. It's unclear why the Seeds::Runner::CheckRun
          # is not compatible with this script. Once resolved, we should use the runner here instead.
          check_suite = ::CheckSuite.create!(
            github_app: GitHub.launch_github_app,
            repository: pull.head_repository,
            head_sha: pull.head_sha,
            head_branch: pull.head_ref,
          )

          Seeds::Objects::CheckRun.create(
            check_suite,
            completed_at: check_run_options[:completed_at],
            conclusion: check_run_options[:conclusion],
            details_url: GitHub.url,
            name: Faker::Superhero.name,
            repository: check_suite.repository,
            status: check_run_options[:status],
            started_at: check_run_options[:started_at],
          )
        end

        case state
        when "closed"
          pull.close(creator)
        when "merged"
          pull.merge(creator)
        end

        pull
      end

      def self.generate_label_name
        candidate = case rand(2)
        when 0
          Faker::House.furniture
        when 1
          Faker::Creature::Animal.name
        when 2
          Faker::Coffee.blend_name
        else
          "default label"
        end
        candidate[0, Labelable::NAME_MAX_LENGTH].downcase
      end

      def self.generate_title
        case rand(5)
        when 0
          Faker::Hacker.say_something_smart
        when 1
          Faker::Books::Lovecraft.sentence(word_count: 8)
        when 2
          Faker::Movie.quote
        when 3
          Faker::Hipster.sentence(word_count: 8)
        when 4
          Faker::Quotes::Shakespeare.romeo_and_juliet_quote
        else
          "default title"
        end
      end

      def self.generate_text_content(max = 3)
        paragraphs = rand(1..max)
        case rand(3)
        when 0
          Faker::Lorem.paragraphs(number: paragraphs).join("\n\n")
        when 1
          Faker::Hipster.paragraphs(number: paragraphs).join("\n\n")
        when 2
          Faker::Books::Lovecraft.paragraphs(number: paragraphs).join("\n\n")
        else
          "default text"
        end
      end

      def self.generate_random_pr_run_check
        now = Time.now
        yesterday = Time.now - (60 * 60 * 24) - (rand(25) * 60 * 60)

        status = %w[completed in_progress].sample

        conclusion = nil
        conclusion = %w[success neutral failure].sample if status == "completed"

        started_at = yesterday - (rand(48) * 60 * 60)

        completed_at = nil
        completed_at = now - (rand(120) * 60) if %w[success failure].include?(conclusion)

        { status:, conclusion:, started_at:, completed_at: }
      end

      def self.add_templates_to_repository(repo:)
        return unless repo.commits

        puts "> adding issue templates to repo..." if verbose?

        ensure_label_exists(repo: repo, label: { name: "bug", color: Faker::Color.hex_color[1..-1] })
        ensure_label_exists(repo: repo, label: { name: "triage", color: Faker::Color.hex_color[1..-1] })
        ensure_label_exists(repo: repo, label: { name: "template", color: Faker::Color.hex_color[1..-1] })
        ensure_label_exists(repo: repo, label: { name: "form", color: Faker::Color.hex_color[1..-1] })

        commit = repo.commits.create({ message: "Add templates", author: repo.owner }) do |files|
          files.add ".github/ISSUE_TEMPLATE/config.yml", <<~YAML
          blank_issues_enabled: true

          contact_links:
            - name: Slack channel #issue_dependencies
              url: https://app.slack.com/client/FOO/BAR
              about: Reach us in slack
          YAML
          files.add SecurityPolicy::FILENAME, SecurityPolicy::TEMPLATE
          files.add ".github/ISSUE_TEMPLATE/bugs.md", <<~MARKDOWN
          ---
          name: Bug report (template)
          about: It's a bug in #{repo.nwo}
          title: "[Bug]: "
          labels: ["bug", "triage", "template"]
          assignees:
            - monalisa
          ---
          This is a bug.
          MARKDOWN
        end

        branch = repo.refs["refs/heads/main"]
        branch.update(commit, repo.owner) if branch
      end

      def self.ensure_label_exists(repo:, label:)
        begin
          repo.labels.create(label) unless repo.labels.where(name: label[:name]).size > 0
        rescue ActiveRecord::RecordNotUnique
          # ignore if this happens
        end
      end

      def self.setup_project_with_issues(issues:)
        monalisa = Seeds::Objects::User.monalisa
        project = Seeds::Objects::MemexProject.create(owner: monalisa, creator: monalisa)
        project.save!

        issues.each do |issue|
          Seeds::Objects::MemexProjectItem.create_issue_or_pull(
            memex_project: project,
            issue_or_pull: issue
          )
        end

        puts "generated project => #{project.permalink}"

        project
      end

      # Borrowed from script/seeds/runners/actions.rb
      def self.setup_launch_github_app_on(repo)
        require_relative "../../create-launch-github-app"

        name = GitHub.launch_github_app_name
        puts ">> Creating GitHub Actions app with name '#{name}'"

        app = ::Integration.find_by(name: name)
        if app.present?
          puts ">> App already exists."
        else
          app = ::CreateLaunchGitHubApp.new.create_app
        end

        puts ">> Installing app on #{repo.nwo} repository"
        installer = repo.owner.organization? ? repo.owner.admins.first : repo.owner
        owner_installation = app.installations_on(repo.owner).first

        if owner_installation.present?
          puts ">> App already installed."
        else
          app.install_on(
            repo.owner,
            repositories: [repo],
            installer: installer,
            entry_point: :seeds_runners_hyperlist_web_create_actions_app
          )
        end
      end
    end
  end
end
