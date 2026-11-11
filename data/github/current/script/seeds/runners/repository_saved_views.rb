# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class RepositorySavedViews < Seeds::Runner
      ISSUE_COUNT = 25

      def self.help
        <<~HELP
          Create saved views for a given repository, along with labels, milestones,
          and issues so the views have content to display.  Enables the sidebar
          and views feature flags automatically.

          Usage:
            bin/seed repository_saved_views --nwo monalisa/smile
            bin/seed repository_saved_views --nwo monalisa/smile --clear

          Options:
            --clear  Remove all existing saved views before creating new ones.
                     Without this flag, existing views are preserved and duplicates are skipped.
        HELP
      end

      LABELS = [
        { name: "bug", color: "d73a4a", description: "Something isn't working" },
        { name: "enhancement", color: "a2eeef", description: "New feature or request" },
        { name: "documentation", color: "0075ca", description: "Improvements or additions to documentation" },
        { name: "good first issue", color: "7057ff", description: "Good for newcomers" },
        { name: "help wanted", color: "008672", description: "Extra attention is needed" },
        { name: "question", color: "d876e3", description: "Further information is requested" },
        { name: "priority: critical", color: "b60205", description: "Must be fixed immediately" },
        { name: "priority: low", color: "c2e0c6", description: "Nice to have" },
        { name: "wontfix", color: "ffffff", description: "This will not be worked on" },
        { name: "duplicate", color: "cfd3d7", description: "This issue already exists" },
        { name: "security", color: "ee0701", description: "Security-related issue" },
        { name: "performance", color: "fbca04", description: "Performance improvement" },
      ].freeze

      MILESTONES = [
        { title: "v1.0", state: "open" },
        { title: "v2.0", state: "open" },
        { title: "Backlog", state: "open" },
        { title: "Shipped", state: "closed" },
      ].freeze

      def self.saved_views(user_login)
        [
          { name: "Everything", query: "is:issue", icon: "inbox", color: "gray",
            description: "All issues, no filters" },
          { name: "Open issues", query: "is:open is:issue sort:created-desc", icon: "issue_opened", color: "green",
            description: "All open issues sorted by newest" },
          { name: "Bug backlog", query: "is:open is:issue label:bug sort:updated-desc", icon: "bug", color: "red",
            description: "Open bugs sorted by recently updated" },
          { name: "Assigned to me", query: "is:open is:issue assignee:@me sort:updated-desc", icon: "person", color: "blue",
            description: "Open issues assigned to you" },
          { name: "Needs triage", query: "is:open is:issue no:label sort:created-desc", icon: "alert", color: "orange",
            description: "Unlabeled open issues needing triage" },
          { name: "Unassigned", query: "is:open is:issue no:assignee sort:created-desc", icon: "people", color: "purple",
            description: "Open issues nobody is working on" },
          { name: "Recently closed", query: "is:closed is:issue sort:updated-desc", icon: "clock", color: "gray",
            description: "Recently closed issues" },
          { name: "v1.0 milestone", query: "is:open is:issue milestone:v1.0 sort:updated-desc", icon: "north_star", color: "green",
            description: "Open issues in the v1.0 milestone" },
          { name: "Feature requests", query: "is:open is:issue label:enhancement sort:reactions-+1-desc", icon: "star", color: "green",
            description: "Most-upvoted feature requests" },
          { name: "Filed by #{user_login}", query: "is:issue author:#{user_login} sort:created-desc", icon: "smiley", color: "purple",
            description: "Issues opened by #{user_login}" },
        ]
      end

      def self.run(options = {})
        require "ruby-progressbar"
        options = options.with_indifferent_access

        nwo = options[:nwo]
        raise "Missing required --nwo parameter. Usage: bin/seed repository_saved_views --nwo owner/repo" unless nwo

        repo = Seeds::Objects::Repository.create_with_nwo(nwo: nwo, setup_master: true)
        creator = Seeds::Objects::User.monalisa

        assignees_set = %w[sv-hubot sv-pr-bot sv-ci-runner sv-triage-lead sv-doc-writer].map do |login|
          Seeds::Objects::User.create(login: login)
        end
        all_users = [creator] + assignees_set

        if repo.owner.organization?
          team = Seeds::Objects::Team.create!(org: repo.owner, name: "Employees")
          assignees_set.each { |u| team.add_member(u) }
        end
        assignees_set.each { |u| repo.add_member(u) unless repo.member?(u) }

        puts "Seeding #{repo.nwo} with #{ISSUE_COUNT} issues and #{saved_views(creator.login).size} saved views..."

        enable_feature_flags(repo)
        create_labels(repo)
        create_milestones(repo, creator)
        create_issues(repo: repo, users: all_users)
        create_saved_views(repo, creator, all_users, clear: options[:clear].present?)

        puts "\n✓ Done! #{GitHub.url}/#{repo.nwo}/issues"
        puts "Note: If saved views return no results, run `bin/elastomer repair` to rebuild the search index."
      end

      def self.enable_feature_flags(repo)
        [:issue_pinned_views, :issue_pinned_views_index_page].each do |flag|
          Seeds::Objects::FeatureFlag.enable(feature_flag: flag, actor: repo)
          puts "  ✓ #{flag}"
        end
      end

      def self.create_labels(repo)
        created = 0
        LABELS.each do |attrs|
          unless repo.labels.find_by(name: attrs[:name])
            repo.labels.create!(attrs)
            created += 1
          end
        end
        puts "  ✓ #{created} labels created"
      end

      def self.create_milestones(repo, actor)
        created = 0
        MILESTONES.each do |attrs|
          unless repo.milestones.find_by(title: attrs[:title])
            repo.milestones.create!(attrs.merge(created_by: actor))
            created += 1
          end
        end
        puts "  ✓ #{created} milestones created"
      end

      def self.create_issues(repo:, users:)
        progress = ProgressBar.create(
          title: "  creating issues",
          total: ISSUE_COUNT,
          format: "%a %b\u{15E7}%i %p%% %t",
          progress_mark: " ",
          remainder_mark: "\u{FF65}",
        ) if Rails.env.development?

        cached_labels = LABELS
        milestones = repo.milestones.to_a
        label_by_name = {}
        repo.labels.each { |l| label_by_name[l.name] = l }

        GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
          ISSUE_COUNT.times do
            progress&.increment

            actor = users.sample
            assignee_list = users.sample(rand(0..3))
            issue_label_hashes = cached_labels.sample(rand(0..3))
            milestone_index = rand(0..milestones.size)
            state = rand(10) < 7 ? "open" : "closed"

            issue = Seeds::Objects::Issue.create(
              repo: repo, actor: actor, title: random_title, body: random_body, state: state,
            )

            dirty = false
            if assignee_list.any?
              issue.assignees = assignee_list
              dirty = true
            end
            issue_label_hashes.each do |lh|
              l = label_by_name[lh[:name]]
              issue.labels.push(l) if l
            end
            dirty = true if issue_label_hashes.any?
            if milestone_index < milestones.size
              issue.milestone = milestones[milestone_index]
              dirty = true
            end
            issue.save! if dirty
          end
        end

        puts "  ✓ #{ISSUE_COUNT} issues created"
      end

      def self.create_saved_views(repo, creator, users, clear: false)
        user_login = users.sample.login

        if clear
          deleted = ::RepositorySearchShortcut.where(repository: repo).delete_all
          puts "  ✓ Cleared #{deleted} existing saved view(s)" if deleted > 0
        end

        existing = ::RepositorySearchShortcut.where(repository: repo)
        existing_names = existing.pluck(:name).to_set
        remaining = ::RepositorySearchShortcut::MAX_PER_REPOSITORY - existing.count

        saved_views(user_login).each do |view|
          next if existing_names.include?(view[:name])

          if remaining <= 0
            puts "  ⚠ Saved view limit reached (#{::RepositorySearchShortcut::MAX_PER_REPOSITORY}). " \
                 "Re-run with --clear to replace existing views."
            break
          end

          Seeds::Objects::RepositorySearchShortcut.create(
            repository: repo, creator: creator,
            name: view[:name], query: view[:query],
            icon: view[:icon], color: view[:color], description: view[:description],
          )
          remaining -= 1
          puts "  ✓ #{view[:name]}"
        end
      end

      def self.random_title
        case rand(6)
        when 0 then Faker::GreekPhilosophers.quote
        when 1 then Faker::Movies::BackToTheFuture.quote
        when 2 then Faker::Movies::PrincessBride.quote
        when 3 then Faker::Movies::HitchhikersGuideToTheGalaxy.quote
        when 4 then Faker::Quotes::Shakespeare.romeo_and_juliet_quote
        when 5 then Faker::TvShows::DrWho.quote
        end
      end

      def self.random_body
        Faker::Lorem.sentence(word_count: 10, supplemental: true, random_words_to_add: 4)
      end
    end
  end
end
