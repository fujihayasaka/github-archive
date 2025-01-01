# typed: false
# frozen_string_literal: true

require "test_helper"

class ContributionCollectorTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers

  def mock_contribution
    Class.new(Contribution) do
      def self.name
        "MockContribution"
      end

      def occurred_at
        Time.now
      end

      def associated_subject
        subject
      end
    end
  end

  def mock_subject(created_at: nil)
    created_at ||= Time.now
    create(:repository, created_at: created_at)
  end

  setup do
    reset_cache
  end

  context "#earliest_activity_time" do
    test "does not raise query warnings" do
      assert_no_query_warnings do
        user = Timecop.freeze("2013-08-01") { create(:user) }

        Timecop.freeze(2016, 7, 26) do
          collector = Contribution::Collector.new(
            user: user,
            viewer: user,
            time_range: 1.week.ago..1.week.since,
          )

          assert collector.earliest_activity_time
        end
      end
    end
  end

  context "#contribution_years" do
    test "returns the years since the user signed up" do
      user = Timecop.freeze("2013-08-01") { create(:user) }

      Timecop.freeze(2016, 7, 26) do
        collector = Contribution::Collector.new(user: user, viewer: user,
                                                time_range: 1.week.ago..1.week.since)
        assert_equal [2016, 2015, 2014, 2013], collector.contribution_years
      end
    end
  end

  context "#enterprise_contributions_user_profile_url" do
    test "gets the URL from the Enterprise installation" do
      user = create(:user)
      enterprise_installation = create(:enterprise_installation, host_name: "someorg.com")
      enterprise_installation.set_login_for(user, "my-business-name")
      EnterpriseContribution.insert_or_update_contribution(user, enterprise_installation,
                                                           Date.current.to_s, 123)
      collector = Contribution::Collector.new(user: user, viewer: user,
                                              time_range: 1.week.ago..1.week.since)

      assert_equal "https://someorg.com/my-business-name",
        collector.enterprise_contributions_user_profile_url
    end

    test "returns nil when there are no Enterprise contributions" do
      user = create(:user)
      enterprise_installation = create(:enterprise_installation, host_name: "someorg.com")
      enterprise_installation.set_login_for(user, "my-business-name")
      collector = Contribution::Collector.new(user: user, viewer: user,
                                              time_range: 1.week.ago..1.week.since)

      assert_nil collector.enterprise_contributions_user_profile_url
    end
  end

  context "#total_enterprise_contributions" do
    test "returns the total number of enterprise contributions" do
      user = create(:user)
      enterprise_installation = create(:enterprise_installation, host_name: "someorg.com")
      enterprise_installation.set_login_for(user, "my-business-name")
      EnterpriseContribution.insert_or_update_contribution(user, enterprise_installation, Date.current.to_s, 123)
      collector = Contribution::Collector.new(user: user, viewer: user,
                                              time_range: 1.week.ago..1.week.since)

      assert_equal 123, collector.total_enterprise_contributions
    end
  end

  context "#earliest_restricted_contribution_date" do
    test "nil when there are no restricted contributions" do
      user = create(:user)
      collector = Contribution::Collector.new(user: user, viewer: nil,
                                              time_range: 1.week.ago..1.week.since)
      assert_nil collector.earliest_restricted_contribution_date
    end

    test "returns date of earliest restricted contribution" do
      user = create(:paid_user, :show_private_contributions)
      repo = Timecop.freeze(1.week.ago) { create(:private_repository, owner: user) }
      Timecop.freeze(1.day.ago) { create(:private_repository, owner: user) }
      time_range = (repo.created_at - 1.month)..(repo.created_at + 1.day)
      collector = Contribution::Collector.new(user: user, viewer: nil, time_range: time_range)
      assert_equal repo.created_at.to_date, collector.earliest_restricted_contribution_date
    end
  end

  context "#latest_restricted_contribution_date" do
    test "nil when there are no restricted contributions" do
      user = create(:user)
      collector = Contribution::Collector.new(user: user, viewer: nil,
                                              time_range: 1.week.ago..1.week.since)
      assert_nil collector.latest_restricted_contribution_date
    end

    test "returns date of most recent restricted contribution" do
      user = create(:paid_user, :show_private_contributions)
      Timecop.freeze(1.week.ago) { create(:private_repository, owner: user) }
      repo = Timecop.freeze(1.day.ago) { create(:private_repository, owner: user) }
      time_range = (repo.created_at - 1.month)..(repo.created_at + 1.day)
      collector = Contribution::Collector.new(user: user, viewer: nil, time_range: time_range)
      assert_equal repo.created_at.to_date, collector.latest_restricted_contribution_date
    end
  end

  context "restricted_contributions_count" do
    test "sums commit contributions when setting enabled" do
      private_owner = create(:user, :show_private_contributions, plan: "medium")

      Timecop.freeze(2016, 10, 1) do
        private_repo = create(:private_repository, owner: private_owner)
        CommitContribution.create \
            repository: private_repo,
            user: private_owner,
            commit_count: 2,
            committed_date: Time.zone.today - 1
        CommitContribution.create \
            repository: private_repo,
            user: private_owner,
            commit_count: 3,
            committed_date: Time.zone.today
        collector = Contribution::Collector.new(user: private_owner, viewer: create(:user),
                                                time_range: 1.day.ago..1.month.from_now)
        assert_equal 6, collector.restricted_contributions_count,
          "includes 5 private commits and 1 private repo"
      end
    end

    test "does not sum commit contributions when setting disabled" do
      private_owner = create(:user, plan: "medium")
      profile_settings = private_owner.profile_settings
      profile_settings.show_private_contribution_count = false
      private_repo = create(:private_repository, owner: private_owner)
      CommitContribution.create \
          repository: private_repo,
          user: private_owner,
          commit_count: 2,
          committed_date: Time.zone.today - 1
      CommitContribution.create \
          repository: private_repo,
          user: private_owner,
          commit_count: 3,
          committed_date: Time.zone.today
      collector = Contribution::Collector.new(user: private_owner, viewer: create(:user),
                                              time_range: 1.month.ago..1.month.from_now)
      assert_equal 0, collector.restricted_contributions_count
    end

    test "counts issue contributions when setting enabled" do
      private_owner = create(:user, :show_private_contributions, plan: "medium")

      Timecop.freeze(2016, 10, 1) do
        private_repo = create(:private_repository, created_at: Time.zone.now, owner: private_owner)
        create :issue, repository: private_repo, user: private_owner, created_at: Time.zone.now
        create :issue, repository: private_repo, user: private_owner, created_at: Time.zone.now
        collector = Contribution::Collector.new(user: private_owner, viewer: create(:user),
                                                time_range: 1.month.ago..1.month.from_now)
        assert_equal 3, collector.restricted_contributions_count,
          "Includes private repo and 2 private issues"
      end
    end

    test "does not count issue contributions when setting disabled" do
      private_owner = create(:user, plan: "medium")
      profile_settings = private_owner.profile_settings
      profile_settings.show_private_contribution_count = false
      private_repo = create(:private_repository, owner: private_owner)
      create :issue, repository: private_repo, user: private_owner
      create :issue, repository: private_repo, user: private_owner
      collector = Contribution::Collector.new(user: private_owner, viewer: create(:user),
                                              time_range: 1.month.ago..1.month.from_now)
      assert_equal 0, collector.restricted_contributions_count
    end
  end

  context "#discussion_contribution_repo_count" do
    test "returns the number of repos the viewer can see the user opened discussions in" do
      Timecop.freeze(2015, 9, 21, 0, 49) do
        user = create(:verified_user)
        repo_1 = create(:private_repository, has_discussions: true)
        repo_1.add_member(user, action: :write)
        create(:discussion, repository: repo_1)
        repo_2 = create(:repository, has_discussions: true)
        create(:discussion, repository: repo_2, user: user)

        collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
        assert_equal 1, collector.discussion_contribution_repo_count
      end
    end
  end

  context "#pull_request_review_repo_count" do
    test "returns the number of repos the viewer can see the user left PR reviews in" do
      Timecop.freeze(2015, 9, 21, 0, 49) do
        user = create(:user)
        pr_author = create(:user)
        repo_1 = create(:private_repository)
        repo_1.add_member(user, action: :write)
        repo_1.add_member(pr_author, action: :write)
        pr1 = create(:pull_request, :disable_disk_access, repository: repo_1, user: pr_author)
        create(:pull_request_review, :commented, pull_request: pr1, user: user)
        repo_2 = create(:repository)
        pr2 = create(:pull_request, :disable_disk_access, repository: repo_2)
        create(:pull_request_review, :approved, pull_request: pr2, user: user)

        collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
        assert_equal 1, collector.pull_request_review_repo_count
      end
    end
  end

  context "#pull_request_contribution_repo_count" do
    test "returns the number of repos the viewer can see the user opened PRs in" do
      Timecop.freeze(2015, 9, 21, 0, 49) do
        user = create(:user)
        repo_1 = create(:private_repository)
        repo_1.add_member(user, action: :write)
        create(:pull_request, :disable_disk_access, user: user, repository: repo_1)
        repo_2 = create(:repository)
        create(:pull_request, :disable_disk_access, user: user, repository: repo_2)

        collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
        assert_equal 1, collector.pull_request_contribution_repo_count
      end
    end
  end

  context "#commit_contribution_repo_count" do
    test "returns the number of repos the viewer can see that the user committed to" do
      Timecop.freeze(2015, 9, 21, 0, 49) do
        user = create(:paid_user)
        repo_1 = create(:private_repository, owner: user)
        repo_2 = create(:repository, owner: user)
        create(:commit_contribution, commit_count: 10, user: user, repository: repo_1,
               committed_date: Date.current)
        create(:commit_contribution, commit_count: 5, user: user, repository: repo_2,
               committed_date: Date.current)

        collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
        assert_equal 1, collector.commit_contribution_repo_count
      end
    end
  end

  context "#total_pull_request_contributions" do
    test "returns the number of PRs the user opened in repos the viewer can access" do
      Timecop.freeze(2015, 9, 21, 0, 49) do
        user = create(:user)
        repo_1 = create(:repository)
        create(:pull_request, :disable_disk_access, user: user, repository: repo_1)
        repo_2 = create(:private_repository)
        repo_2.add_member(user, action: :write)
        create(:pull_request, :disable_disk_access, user: user, repository: repo_2)

        collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
        assert_equal 1, collector.total_pull_request_contributions
      end
    end
  end

  context "#total_issue_contributions" do
    test "returns the number of issues the user opened in repos the viewer can access" do
      Timecop.freeze(2015, 9, 21, 0, 49) do
        user = create(:user)
        repo_1 = create(:repository)
        create(:issue, user: user, repository: repo_1, created_at: Time.zone.now)
        repo_2 = create(:private_repository)
        create(:issue, user: user, repository: repo_2, created_at: Time.zone.now)

        collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
        assert_equal 1, collector.total_issue_contributions
      end
    end
  end

  context "#total_discussion_contributions" do
    test "returns the number of discussions the user opened in repos the viewer can access" do
      Timecop.freeze(2015, 9, 21, 0, 49) do
        user = create(:verified_user)
        repo_1 = create(:repository, has_discussions: true)
        create(:discussion, user: user, repository: repo_1, created_at: Time.zone.now)
        repo_2 = create(:private_repository, has_discussions: true)
        create(:discussion, user: user, repository: repo_2, created_at: Time.zone.now)

        collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
        assert_equal 1, collector.total_discussion_contributions
      end
    end
  end

  context "#total_repository_contributions" do
    test "returns the number of repos the user created that the viewer can access" do
      Timecop.freeze(2015, 9, 21, 0, 49) do
        user = create(:paid_user)
        create(:repository, owner: user)
        create(:private_repository, owner: user)

        collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
        assert_equal 1, collector.total_repository_contributions
      end
    end
  end

  context "#total_contributed_commits" do
    test "returns the total number of commits for a user in repos the viewer can access" do
      Timecop.freeze(2015, 9, 21, 0, 49) do
        user = create(:paid_user)
        repo_1 = create(:private_repository, owner: user)
        repo_2 = create(:repository, owner: user)
        create(:commit_contribution, commit_count: 10, user: user, repository: repo_1,
               committed_date: Date.current)
        create(:commit_contribution, commit_count: 5, user: user, repository: repo_2,
               committed_date: Date.current)

        collector = Contribution::Collector.new(user: user,
                                                time_range: 1.day.ago..1.day.since)
        assert_equal 5, collector.total_contributed_commits
      end
    end
  end

  context "#started_at" do
    test "returns the starting time of the collection" do
      from = 1.month.ago
      user = create(:user)
      collector = Contribution::Collector.new(user: user, viewer: user,
                                              time_range: from..Time.zone.now)

      assert_equal from, collector.started_at
    end
  end

  context "#ended_at" do
    test "returns the ending time of the collection" do
      to = 1.day.ago
      user = create(:user)
      collector = Contribution::Collector.new(user: user, viewer: user,
                                              time_range: 1.month.ago..to)

      assert_equal to, collector.ended_at
    end
  end

  context "#prior_activity_fetcher" do
    test "returns a PriorActivityCollectorFetcher" do
      user = Timecop.freeze("2016-05-15") { create(:user) }
      viewer = create(:user)
      from = Time.parse("2016-06-01")
      to = from.end_of_month
      org = create(:organization)
      contrib_classes = [Contribution::JoinedOrganization]

      collector = Contribution::Collector.new(
        user: user,
        viewer: viewer,
        time_range: from..to,
        organization_id: org.id,
        contribution_classes: contrib_classes,
      )

      assert_equal collector, collector.prior_activity_fetcher.collector
    end
  end

  context "#ends_in_current_month?" do
    test "false if not viewing the current month" do
      user = Timecop.freeze("2017-01-01") { create(:user) }
      from = user.created_at.beginning_of_month
      to = from.end_of_month
      collector = Contribution::Collector.new(user: user, viewer: user, time_range: from..to)

      refute_predicate collector, :ends_in_current_month?
    end

    test "true if viewing the current month" do
      Timecop.freeze do
        user = create(:user)
        from = user.created_at.beginning_of_month
        to = from.end_of_month
        collector = Contribution::Collector.new(user: user, viewer: user, time_range: from..to)

        assert_predicate collector, :ends_in_current_month?
      end
    end
  end

  context "#date_range" do
    test "returns the range of dates covered by the collector" do
      user = create(:user)
      from = 1.month.ago
      to = Time.zone.now
      collector = Contribution::Collector.new(user: user, viewer: user, time_range: from..to)

      assert_equal from.to_date..to.to_date, collector.date_range
    end
  end

  context "#organizations_contributed_to" do
    test "includes specified org even when there are no contributions within it" do
      org_member = viewer = create(:user)
      org = create(:organization)
      create(:repository, owner: org) # org must own a repo since we INNER JOIN to repositories
      collector = Contribution::Collector.new(user: org_member, viewer: viewer,
                                              time_range: 1.month.ago..Time.zone.now,
                                              contribution_classes: [Contribution::CreatedIssue])

      assert_equal [org], collector.organizations_contributed_to(selected_organization_id: org.id)
    end

    test "doesn't include orgs the user belongs to if the user didn't contribute to org repos" do
      org_member = viewer = create(:user)
      org = create(:organization)
      org.add_member(org_member)
      create(:repository, owner: org) # org must own a repo since we INNER JOIN to repositories
      collector = Contribution::Collector.new(user: org_member, viewer: viewer,
                                              time_range: 1.month.ago..Time.zone.now,
                                              contribution_classes: [Contribution::CreatedIssue])

      assert_empty collector.organizations_contributed_to
    end

    test "includes orgs that the user contributed to and is not a member of" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      contributor = create(:user)
      create(:issue, repository: repo, user: contributor)
      viewer = create(:user)

      collector = Contribution::Collector.new(user: contributor, viewer: viewer,
                                              time_range: 1.month.ago..Time.zone.now,
                                              contribution_classes: [Contribution::CreatedIssue])

      assert_equal [org], collector.organizations_contributed_to
    end

    test "doesn't include an org if no org contributions are visible to viewer" do
      contributor = create(:user)
      viewer = create(:user)

      org = create(:organization, admin: contributor)
      repo = create(:private_repository, owner: org)
      create(:issue, repository: repo, user: contributor)

      collector = Contribution::Collector.new(user: contributor, viewer: viewer,
                                              time_range: 1.month.ago..Time.zone.now,
                                              contribution_classes: [Contribution::CreatedIssue])

      assert_empty collector.organizations_contributed_to
    end

    test "raises an error if called on a collector scoped by organization id" do
      contributor = viewer = create(:user)
      scoping_organization_id = 123

      collector = Contribution::Collector.new(user: contributor, viewer: viewer,
                                              time_range: 1.month.ago..Time.zone.now,
                                              organization_id: scoping_organization_id)

      assert_raises Contribution::Collector::DataNotAvailable do
        collector.organizations_contributed_to
      end
    end

    test "excludes orgs specified by excluded_organization_ids argument" do
      contributor = create :user
      viewer = create :user
      excluded_org, other_org = create_pair(:organization) do |org|
        repo = create :repository, owner: org
        create :issue, repository: repo, user: contributor
      end

      collector = Contribution::Collector.new(
        user: contributor, viewer: viewer,
        time_range: 1.month.ago..Time.zone.now,
        contribution_classes: [Contribution::CreatedIssue],
        excluded_organization_ids: [excluded_org.id],
        lightweight: true,
      )

      assert_equal [other_org], collector.organizations_contributed_to
    end

    test "handles nil excluded_organization_ids argument" do
      contributor = create :user
      viewer = create :user
      org_one, org_two = create_pair(:organization) do |org|
        repo = create :repository, owner: org
        create :issue, repository: repo, user: contributor
      end

      collector = Contribution::Collector.new(
        user: contributor, viewer: viewer,
        time_range: 1.month.ago..Time.zone.now,
        contribution_classes: [Contribution::CreatedIssue],
        excluded_organization_ids: nil,
        lightweight: true,
      )

      assert_same_elements [org_one, org_two], collector.organizations_contributed_to
    end

    test "caches calls that trigger fetch_contributions_if_necessary" do
      with_cache_enabled do
        user = create(:user, plan: :silver)
        org = create(:organization)
        base_time = Date.current
        time_range = (base_time - 1.year)..base_time
        created_at = base_time - 3.months
        repo = create(:repository, owner: org)

        # Create issues
        create_list(:issue, 3, user: user, repository: repo)

        # create commits
        CommitContribution.create \
          repository: repo,
          user: user,
          commit_count: 1,
          committed_date: created_at

        # Create pull requests
        create(:pull_request, :disable_disk_access, user: user, created_at: created_at)

        # Create code review
        # The :commented trait is required here since the default is pending and won't show up
        # as a contribution.
        create(:pull_request_review, :disable_disk_access, :commented,
          user: user,
          submitted_at: created_at
        )

        # Warm cache
        collector = Contribution::Collector.new(user: user, time_range: time_range)
        orgs = collector.organizations_contributed_to

        # Ensure we don't fetch data again
        Contribution::CreatedCommit.expects(:subjects_for).never
        cached_collector = Contribution::Collector.new(user: user, time_range: time_range)
        cached_orgs = cached_collector.organizations_contributed_to

        # But that the results of each call are the same
        assert orgs.length > 0
        assert orgs, cached_orgs
      end
    end
  end

  context "#single_day?" do
    test "false when time_range specifies a range greater than 1 day" do
      user = build(:user)
      from = Time.parse("2016-08-01")
      to = Time.parse("2016-08-05")
      collector = Contribution::Collector.new(user: user, viewer: user, time_range: from..to)

      refute_predicate collector, :single_day?
    end

    test "true when time_range specifies a range <= 1 day" do
      user = build(:user)
      from = Time.zone.now.beginning_of_day
      to = from + 5.minutes
      collector = Contribution::Collector.new(user: user, viewer: user, time_range: from..to)

      assert_predicate collector, :single_day?
    end
  end

  context "initializing a new contributions collector" do
    test "considers all contribution classes by default" do
      user = create(:user)
      collector = Contribution::Collector.new(
        user: user,
        time_range: 1.day.ago..1.day.since,
      )

      contribution_classes = [
        Contribution::AnsweredDiscussion,
        Contribution::CreatedCommit,
        Contribution::CreatedDiscussion,
        Contribution::CreatedIssue,
        Contribution::CreatedPullRequest,
        Contribution::CreatedRepository,
        Contribution::JoinedGitHub,
        Contribution::JoinedOrganization,
        Contribution::EnterpriseContributionInfo,
        Contribution::CreatedPullRequestReview,
      ]

      assert_same_elements contribution_classes, collector.contribution_classes
    end

    test "measures how long it takes to fetch individual contributions" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      user = create(:user)
      contribution_class = Class.new(Contribution) do
        def self.name
          "Contribution::AnotherModule::MyPersonalContribution"
        end
      end
      collector = Contribution::Collector.new(
        user: user,
        time_range: 1.day.ago..1.day.since,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      collector.visible_contributions_of(contribution_class)

      timing = GitHub.dogstats.distributions("contributions.fetch.my_personal_contribution")
      assert_equal 1, timing.length
    end

    test "does not enable contribution fetchers for user not in the feature flag" do
      user = create(:user)
      GitHub.flipper[:contribution_fetchers].disable(user)

      Contribution::Accessor.expects(:new).with do |args|
        args[:use_contribution_fetchers] == false
      end

      collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
    end

    test "enables contribution fetchers for users in the feature flag" do
      user = create(:user)
      GitHub.flipper[:contribution_fetchers].enable(user)

      Contribution::Accessor.expects(:new).with do |args|
        args[:use_contribution_fetchers] == true
      end

      collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.since)
    end

    context "flagged contribution classes" do
      test "ignores flagged contribution classes by default" do
        user = create(:user)
        user.flag_contribution_classes!([Contribution::CreatedCommit])
        collector = Contribution::Collector.new(
          user: user,
          time_range: 1.day.ago..1.day.since,
        )

        refute_includes collector.contribution_classes, Contribution::CreatedCommit
      end

      test "consideres all contributions when unflagging all classes" do
        user = create(:user)
        user.unflag_contribution_classes!
        collector = Contribution::Collector.new(
          user: user,
          time_range: 1.day.ago..1.day.since,
        )

        assert_same_elements Contribution::Collector::CONTRIBUTION_CLASSES,
          collector.contribution_classes
      end
    end

    test "allows filtering by organization" do
      org_id = 123
      user = create(:user)
      date_range = Date.yesterday..Date.tomorrow
      contribution_class = Contribution::CreatedIssue
      Contribution::CreatedIssue.expects(:subjects_for).once.with(
        user,
        organization_id: org_id,
        date_range: date_range,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([])
      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        organization_id: org_id,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      collector.visible_contributions_of(contribution_class)
    end
  end

  context "#first_pull_request_contribution" do
    test "returns contribution when it occurs within the time range" do
      user = create(:user)
      pull = create(:pull_request, :disable_disk_access, user: user)
      time_range = pull.contribution_time.beginning_of_month..pull.contribution_time.end_of_month
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      result = collector.first_pull_request_contribution

      assert_instance_of Contribution::CreatedPullRequest, result
      assert_equal pull, result.pull_request
    end

    test "returns nil when the user has no issues" do
      user = create(:user)
      time_range = 1.week.ago..1.week.since
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      assert_nil collector.first_pull_request_contribution
    end

    test "returns nil when contrib occurs outside the time range" do
      user = create(:user)
      pull = create(:pull_request, :disable_disk_access, user: user)
      time = pull.created_at + 1.year
      time_range = time.beginning_of_month..time.end_of_month
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      assert_nil collector.first_pull_request_contribution
    end

    test "returns a restricted contribution when appropriate" do
      user = create(:user, :show_private_contributions)
      repo = create(:private_repository, owner: user)
      pull = create(:pull_request, :disable_disk_access, repository: repo, user: user)
      time_range = pull.contribution_time.beginning_of_month..pull.contribution_time.end_of_month
      collector = Contribution::Collector.new(
        user: user,
        time_range: time_range,
        viewer: create(:user),
      )

      result = collector.first_pull_request_contribution

      assert_predicate result, :restricted?
    end
  end

  context "#first_issue_contribution" do
    test "returns contribution when it occurs within the time range" do
      user = create(:user)
      issue = create(:issue, user: user)
      time_range = issue.contribution_time.beginning_of_month..issue.contribution_time.end_of_month
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      result = collector.first_issue_contribution

      assert_instance_of Contribution::CreatedIssue, result
      assert_equal issue, result.issue
    end

    test "returns nil when the user has no issues" do
      user = create(:user)
      time_range = 1.week.ago..1.week.since
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      assert_nil collector.first_issue_contribution
    end

    test "returns nil when contrib occurs outside the time range" do
      user = create(:user)
      issue = create(:issue, user: user)
      time = issue.created_at + 1.year
      time_range = time.beginning_of_month..time.end_of_month
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      assert_nil collector.first_issue_contribution
    end

    test "returns a restricted contribution when appropriate" do
      user = create(:user, :show_private_contributions)
      repo = create(:private_repository, owner: user)
      issue = create(:issue, repository: repo, user: user)
      time_range = issue.contribution_time.beginning_of_month..issue.contribution_time.end_of_month
      collector = Contribution::Collector.new(
        user: user,
        time_range: time_range,
        viewer: create(:user),
      )

      result = collector.first_issue_contribution

      assert_predicate result, :restricted?
    end
  end

  context "#first_repository_contribution" do
    test "returns contribution when it occurs within the time range" do
      user = create(:user)
      repo = create(:repository, owner: user)
      time_range = repo.created_at.beginning_of_month..repo.created_at.end_of_month
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      result = collector.first_repository_contribution

      assert_instance_of Contribution::CreatedRepository, result
      assert_equal repo, result.repository
    end

    test "returns nil when the user has no repositories" do
      user = create(:user)
      time_range = 1.week.ago..1.week.since
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      assert_nil collector.first_repository_contribution
    end

    test "returns nil when contrib occurs outside the time range" do
      user = create(:user)
      repo = create(:repository, owner: user)
      time = repo.created_at + 1.year
      time_range = time.beginning_of_month..time.end_of_month
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      assert_nil collector.first_repository_contribution
    end

    test "returns a restricted contribution when appropriate" do
      user = create(:user, :show_private_contributions)
      repo = create(:private_repository, owner: user)
      time_range = repo.created_at.beginning_of_month..repo.created_at.end_of_month
      collector = Contribution::Collector.new(
        user: user,
        time_range: time_range,
        viewer: create(:user),
      )

      result = collector.first_repository_contribution
      assert_predicate result, :restricted?
    end
  end

  context "#joined_github_contribution" do
    test "returns contribution when it occurs within the time range" do
      user = create(:user)
      time_range = user.created_at.beginning_of_month..user.created_at.end_of_month
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      result = collector.joined_github_contribution

      assert_instance_of Contribution::JoinedGitHub, result
      assert_equal user, result.user
    end

    test "returns nil when contrib occurs outside the time range" do
      user = create(:user)
      time = user.created_at + 1.year
      time_range = time.beginning_of_month..time.end_of_month
      collector = Contribution::Collector.new(user: user, time_range: time_range)

      assert_nil collector.joined_github_contribution
    end
  end

  context "#contribution_counts" do
    test "returns ContributionType objects for each count type in the given period" do
      user = create(:issue).user

      collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.from_now,
        contribution_classes: [Contribution::CreatedIssue])

      assert_equal 1, collector.contribution_counts.count
      assert_equal "Issues", collector.contribution_counts.first.contribution_type
      assert_equal 1, collector.contribution_counts.first.count
    end

    test "does not include counts from restricted contributions if the user does not want them shown" do
      user = create(:user, plan: :silver)
      private_repository = create(:private_repository, owner: user)
      create(:issue, user: user, repository: private_repository)

      collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.from_now, contribution_classes: [Contribution::CreatedIssue])

      assert_equal 0, collector.contribution_counts.count
    end

    test "includes counts from restricted contributions if the user wants them shown" do
      user = create(:user, :show_private_contributions, plan: :silver)

      private_repository = create(:private_repository, owner: user)
      create(:issue, user: user, repository: private_repository)

      collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.from_now, contribution_classes: [Contribution::CreatedIssue])

      assert_equal 1, collector.contribution_counts.count
      assert_equal "Issues", collector.contribution_counts.first.contribution_type
      assert_equal 1, collector.contribution_counts.first.count
    end

    test "percents should add up to 100" do
      user = create(:user, :show_private_contributions, plan: :silver)
      base_time = Date.current
      time_range = (base_time - 1.year)..base_time
      created_at = base_time - 3.months
      repo = create(:repository, owner: user)

      # Create issues
      create_list(:issue, 3, user: user, repository: repo)

      # create commits
      CommitContribution.create \
        repository: repo,
        user: user,
        commit_count: 1,
        committed_date: created_at

      # Create pull requests
      create(:pull_request, :disable_disk_access, user: user, created_at: created_at)

      # Create code review
      # The :commented trait is required here since the default is pending and won't show up
      # as a contribution.
      create(:pull_request_review, :disable_disk_access, :commented,
        user: user,
        submitted_at: created_at
      )

      # 3 issues | 1 commit | 1 pull request | 1 code review
      # When using #round on percents we get 50,17,17,17 for a total of 101.
      # When using #floored on percents we get 50,16,16,16 for a total of 98.

      collector = Contribution::Collector.new(user: user, time_range: time_range)

      total = collector.contribution_counts.map(&:percentage).sum

      assert_equal 100, total
    end

    # This is a bit of a contrived test, since a contribution type with zero contributions
    # wouldn't normally show up in the result from `contribution_counts_by_class_name`. This test
    # ensures that the rounding balancing doesn't falsly add any extra percentages to
    # types with zero contributions if that ever changes.
    #
    test "if a contribution count/percent is 0 it should stay 0" do
      user = create(:user, :show_private_contributions, plan: :silver)
      base_time = Date.current
      time_range = (base_time - 1.year)..base_time

      collector = Contribution::Collector.new(user: user, time_range: time_range)
      Contribution::Accessor.any_instance.stubs(:counts_by_class_name).returns(
        "Contribution::CreatedCommit" => 0,
        "Contribution::CreatedIssue" => 3,
        "Contribution::CreatedPullRequest" => 1,
        "Contribution::CreatedPullRequestReview" => 1,
      )

      commit_contribution = collector.contribution_counts.find do |contrib_count|
        contrib_count.contribution_type == "Commits"
      end

      assert_equal 0, commit_contribution.count
      assert_equal 0, commit_contribution.percentage
    end

    test "caches result" do
      with_cache_enabled do
        user = create(:user, plan: :silver)
        base_time = Date.current
        time_range = (base_time - 1.year)..base_time
        created_at = base_time - 3.months
        repo = create(:repository, owner: user)

        # Create issues
        create_list(:issue, 3, user: user, repository: repo)

        # create commits
        CommitContribution.create \
          repository: repo,
          user: user,
          commit_count: 1,
          committed_date: created_at

        # Create pull requests
        create(:pull_request, :disable_disk_access, user: user, created_at: created_at)

        # Create code review
        # The :commented trait is required here since the default is pending and won't show up
        # as a contribution.
        create(:pull_request_review, :disable_disk_access, :commented,
          user: user,
          submitted_at: created_at
        )

        # Warm cache
        collector = Contribution::Collector.new(user: user, time_range: time_range)
        counts = collector.contribution_counts

        # Ensure we don't fetch data again
        Contribution::CreatedCommit.expects(:subjects_for).never
        cached_collector = Contribution::Collector.new(user: user, time_range: time_range)
        cached_counts = cached_collector.contribution_counts

        # But that the results of each call are the same
        assert counts, cached_counts
      end
    end

    test "tracks execution time for uncached calls" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user)

      collector = Contribution::Collector.new(
        user: user,
        time_range: 1.day.ago..1.day.since,
      )

      collector.visible_repository_ids

      timing = GitHub.dogstats.distributions("contributions.accessor.load")
      assert_equal 1, timing.length
    end
  end

  context "#repository_contribution_counts" do
    test "returns an empty list for a large bot user" do
      large_bot_user = create(:user, id: User::ContributionsDependency::LARGE_BOT_ACCOUNTS.first)
      repo = create(:repository)
      issue = create(:issue, repository: repo, user: large_bot_user)
      time_range = (issue.created_at - 1.month)..(issue.created_at + 1.month)
      collector = Contribution::Collector.new(user: large_bot_user, time_range: time_range)

      assert_empty collector.repository_contribution_counts
    end

    test "returns RepositoryContributionType objects for each repository in the given period" do
      user = create(:user)
      repo = create(:issue, user: user).repository

      collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.from_now, contribution_classes: [Contribution::CreatedIssue])

      assert_equal 1, collector.repository_contribution_counts.count
      assert_equal repo.id, collector.repository_contribution_counts.first.id
      assert_equal 1, collector.repository_contribution_counts.first.count
    end

    test "does not include counts from restricted contributions if the user does not want them shown" do
      user = create(:user, plan: :silver)
      private_repository = create(:private_repository, owner: user)
      create(:issue, user: user, repository: private_repository)

      collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.from_now, contribution_classes: [Contribution::CreatedIssue])

      assert_equal 0, collector.repository_contribution_counts.count
    end

    # this method should not include restricted contributions (even if show_private_contribution_count is true) because
    # it exposes information about the repositories and not just a sanitized count of contributions
    test "does not include counts from restricted contributions even if show_private_contribution_count is true" do
      user = create(:user, :show_private_contributions, plan: :silver)

      private_repository = create(:private_repository, owner: user)
      create(:issue, user: user, repository: private_repository)

      collector = Contribution::Collector.new(user: user, time_range: 1.day.ago..1.day.from_now, contribution_classes: [Contribution::CreatedIssue])

      assert_equal 0, collector.repository_contribution_counts.count
    end
  end

  def stub_contribution_class(contribution_class, user:, subjects:, date_range:, occurred_on:)
    contribution_class.any_instance.stubs(:occurred_on).returns(occurred_on)
    contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
    ).returns(subjects)
  end

  context "#contribution_count_by_day" do
    test "only counts restricted contributions when user wants to show private contributions" do
      user = create(:user, :show_private_contributions)
      repo = create(:private_repository, owner: user)

      date_range = Date.yesterday..Date.tomorrow

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [Contribution::CreatedRepository],
        lightweight: true,
      )

      refute_empty collector.contribution_count_by_day

      user.profile_settings.show_private_contribution_count = false

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [Contribution::CreatedRepository],
        lightweight: true,
      )

      assert_empty collector.contribution_count_by_day
    end

    test "counts contributions per day" do
      user = create(:user, :show_private_contributions)

      date_range = Date.yesterday..Date.tomorrow
      occurred_on_1 = date_range.begin
      occurred_on_2 = date_range.end

      contribution_class = Class.new(mock_contribution)
      stub_contribution_class(contribution_class,
        user: user,
        subjects: [mock_subject, mock_subject],
        date_range: date_range,
        occurred_on: occurred_on_1,
      )

      bulk_contribution_class = Class.new(mock_contribution) do
        def contributions_count
          10
        end
      end
      stub_contribution_class(bulk_contribution_class,
        user: user,
        subjects: [mock_subject, mock_subject],
        date_range: date_range,
        occurred_on: occurred_on_2,
      )

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class, bulk_contribution_class],
        lightweight: true,
      )

      expected = {
        occurred_on_1 => 2,
        occurred_on_2 => 20,
      }

      assert_equal expected, collector.contribution_count_by_day
    end

    test "excludes contributions associated with an orphan repository" do
      user = create(:user, :show_private_contributions)
      private_repo = create(:private_repository)

      date_range = Date.yesterday..Date.tomorrow

      contribution_class = Class.new(mock_contribution) do
        def repository_id
          subject.id
        end

        def occurred_at
          subject.created_at
        end
      end

      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([private_repo])

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true
      )

      assert_equal 1, collector.contribution_count_by_day.count

      private_repo.owner.delete # do not trigger callbacks

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      assert_empty collector.contribution_count_by_day
    end

    test "has daily counts when user has enabled private contrib counts" do
      user = create(:paid_user, :show_private_contributions)
      private_repo, issue1 = Timecop.freeze("2018-11-01T00:08:21Z") do
        repo = create(:private_repository, owner: user, created_at: Time.zone.now)
        issue = create(:issue, repository: repo, user: user, created_at: Time.zone.now)
        [repo, issue]
      end
      issue2 = Timecop.freeze("2018-11-04T00:08:21Z") do
        create(:issue, repository: private_repo, user: user, created_at: Time.zone.now)
      end
      collector = Contribution::Collector.new(
        user: user,
        time_range: issue1.created_at.beginning_of_month..issue2.created_at.end_of_month,
      )
      expected = {
        issue1.created_at.to_date => 2, # private issue + private repo
        issue2.created_at.to_date => 1,  # private issue
      }

      assert_equal expected, collector.contribution_count_by_day
    end

    test "caches results" do
      with_cache_enabled do
        user = create(:user, plan: :silver)
        base_time = Date.current
        time_range = (base_time - 1.year)..base_time
        created_at = base_time - 3.months
        repo = create(:repository, owner: user)

        create(:issue, user: user, repository: repo, created_at: created_at)

        # Warm cache
        collector = Contribution::Collector.new(user: user, time_range: time_range)
        count_by_day = collector.contribution_count_by_day

        # Ensure we don't fetch data again
        Contribution::CreatedCommit.expects(:subjects_for).never
        cached_collector = Contribution::Collector.new(user: user, time_range: time_range)
        cached_count_by_day = cached_collector.contribution_count_by_day

        # But that the results of each call are the same
        assert_equal count_by_day, cached_count_by_day
      end
    end
  end

  context "#visible_repository_ids" do
    test "excludes repository_ids with no visible contributions" do
      user = create(:user, plan: "medium")
      private_repository = create(:private_repository)
      public_repository = create(:repository)
      date_range = Date.yesterday..Date.tomorrow

      contribution_class = Class.new(mock_contribution) do
        def repository_id
          subject.id
        end

        def occurred_at
          Time.zone.now
        end
      end

      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([private_repository, public_repository])

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      assert_equal [public_repository.id], collector.visible_repository_ids
    end

    test "excludes ids of orphaned repositories" do
      user = create(:user)
      repo = create(:repository)

      date_range = Date.yesterday..Date.tomorrow

      contribution_class = Class.new(mock_contribution) do
        def repository_id
          subject.id
        end

        def occurred_at
          subject.created_at
        end
      end
      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([repo])

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      assert_equal [repo.id], collector.visible_repository_ids

      repo.owner.delete # do not trigger callbacks
      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      assert_empty collector.visible_repository_ids
    end
  end

  def collector_for(
    contribution_class,
    first_subject:,
    is_restricted:,
    time_range:,
    viewer: nil,
    user: create(:user),
    organization_id: nil,
    excluded_organization_ids: []
  )
    contribution_class.stubs(:first_subject_for).with(
      user, excluded_organization_ids: excluded_organization_ids
    ).returns(first_subject)

    Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(is_restricted)

    Contribution::Collector.new(
      user: user, time_range: time_range, viewer: viewer, organization_id: organization_id,
    )
  end

  context "#first_contribution_of" do
    test "returns nil when there is no first contribution" do
      collector = Contribution::Collector.new(
        user: create(:user),
        time_range: 1.day.ago..1.day.since,
      )

      assert_nil collector.first_contribution_of(Contribution)
    end

    test "returns nil when first contribution does not match organization ID" do
      contribution_class = Class.new(mock_contribution) do
        def organization_id
          1
        end
      end
      collector = collector_for(contribution_class,
        first_subject: mock_subject,
        is_restricted: false,
        time_range: 1.day.ago..1.day.since,
        organization_id: 2,
      )

      assert_nil collector.first_contribution_of(contribution_class)
    end

    test "returns first contribution when it matches specified organization ID" do
      contribution_class = Class.new(mock_contribution) do
        def organization_id
          1
        end
      end
      collector = collector_for(contribution_class,
        first_subject: mock_subject,
        is_restricted: false,
        time_range: 1.day.ago..1.day.since,
        organization_id: 1,
      )

      assert collector.first_contribution_of(contribution_class)
    end

    test "returns nil when first contribution does not have an organization ID and one is specified" do
      contribution_class = Class.new(mock_contribution)
      collector = collector_for(contribution_class,
        first_subject: mock_subject,
        is_restricted: false,
        time_range: 1.day.ago..1.day.since,
        organization_id: 1,
      )

      assert_nil collector.first_contribution_of(contribution_class)
    end

    test "returns the first contribution when it is visible and in the given time range" do
      contribution_class = Class.new(mock_contribution) do
        def occurred_at
          Time.zone.now
        end
      end
      collector = collector_for(contribution_class,
        first_subject: mock_subject,
        is_restricted: false,
        time_range: 1.day.ago..1.day.since,
      )

      assert collector.first_contribution_of(contribution_class)
    end

    test "ignores the first contribution when it is visible but not in the given time range" do
      contribution_class = Class.new(mock_contribution) do
        def occurred_at
          2.days.ago
        end
      end
      collector = collector_for(contribution_class,
        first_subject: mock_subject,
        is_restricted: false,
        time_range: 1.day.ago..1.day.since,
      )

      assert_nil collector.first_contribution_of(contribution_class)
    end

    context "User#show_private_contribution_count? is 'false'" do
      test "ignores the first contribution when it is restricted" do
        contribution_class = Class.new(mock_contribution) do
          def occurred_at
            Time.zone.now
          end
        end
        collector = collector_for(contribution_class,
          first_subject: mock_subject,
          is_restricted: true,
          time_range: 1.day.ago..1.day.since,
        )

        assert_nil collector.first_contribution_of(contribution_class)
      end
    end

    context "User#show_private_contribution_count? is 'true'" do
      test "returns the first contribution when it is restricted" do
        contribution_class = Class.new(mock_contribution) do
          def occurred_at
            Time.zone.now
          end
        end
        user = create(:user, :show_private_contributions)
        collector = collector_for(contribution_class,
          user: user,
          first_subject: mock_subject,
          is_restricted: true,
          time_range: 1.day.ago..1.day.since,
        )

        contribution = collector.first_contribution_of(contribution_class)
        assert_equal user, contribution.user
        assert_instance_of Contribution::RestrictedContribution, contribution
      end
    end
  end

  context "#first_visible_contribution" do
    test "returns the first visible contribution of any type" do
      user = create(:user)
      date_range = Date.yesterday..Date.tomorrow
      oldest_occurred_at = 1.day.ago

      contribution_class = Class.new(mock_contribution) do
        def occurred_at
          subject.created_at
        end
      end
      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([mock_subject, mock_subject])

      other_contribution_class = Class.new(contribution_class)
      other_contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([mock_subject, mock_subject(created_at: oldest_occurred_at)])

      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(false)

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class, other_contribution_class],
        lightweight: true,
      )

      assert_equal oldest_occurred_at.to_i, collector.first_visible_contribution.occurred_at.to_i
    end

    test "ignores restricted contributions" do
      user = create(:user)
      date_range = Date.yesterday..Date.tomorrow

      contribution_class = Class.new(mock_contribution) do
        def occurred_at
          subject
        end
      end
      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([mock_subject(created_at: 5.minutes.ago), mock_subject(created_at: 5.hours.ago)])

      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(true)

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      assert_nil collector.first_visible_contribution
    end
  end

  context "#any_restricted_contribution?" do
    test "returns false for a large bot user" do
      large_bot_user = create(:user, :show_private_contributions)
      large_bot_user.stubs(:large_bot_account?).returns(true)
      private_repo = create(:private_repository, owner: large_bot_user)
      time_range = (private_repo.created_at - 1.day)..(private_repo.created_at + 1.day)

      collector = Contribution::Collector.new(
        user: large_bot_user,
        time_range: time_range,
        contribution_classes: [Contribution::CreatedRepository],
        lightweight: true,
      )

      refute_predicate collector, :any_restricted_contribution?
    end
  end

  context "#any_contribution?" do
    test "returns false for a large bot user" do
      large_bot_user = create(:user)
      large_bot_user.stubs(:large_bot_account?).returns(true)
      date_range = Date.yesterday..Date.tomorrow
      contribution_class = Contribution
      contribution_class.stubs(:subjects_for).with(
        large_bot_user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([mock_subject])
      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(false)

      collector = Contribution::Collector.new(
        user: large_bot_user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      refute_predicate collector, :any_contribution?
    end

    test "returns true if there is a visible contribution" do
      user = create(:user)
      date_range = Date.yesterday..Date.tomorrow
      contribution_class = Class.new(mock_contribution) do
        def occurred_at
          Time.zone.now
        end
      end
      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([mock_subject])

      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(false)

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      assert_predicate collector, :any_contribution?
    end

    test "returns true if there is a restricted contribution" do
      user = create(:user, :show_private_contributions)
      date_range = Date.yesterday..Date.tomorrow
      contribution_class = Class.new(mock_contribution) do
        def occurred_at
          Time.zone.now
        end
      end
      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([mock_subject])

      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(true)

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      assert_predicate collector, :any_contribution?
    end

    test "returns false if there is only a contribution that doesn't match the org filter" do
      user = create(:user)
      org = create(:organization)
      time_range = user.created_at.beginning_of_month..user.created_at.end_of_month
      contribution_class = Contribution::JoinedGitHub
      collector = Contribution::Collector.new(
        user: user,
        time_range: time_range,
        contribution_classes: [contribution_class],
        organization_id: org.id,
        lightweight: true,
      )

      refute_predicate collector, :any_contribution?
    end

    test "returns false if there is no contribution" do
      user = create(:user)
      date_range = Date.yesterday..Date.tomorrow
      contribution_class = Contribution
      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([])

      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(false)

      collector = Contribution::Collector.new(
        user: user,
        time_range: date_range,
        contribution_classes: [contribution_class],
        lightweight: true,
      )

      refute_predicate collector, :any_contribution?
    end
  end

  context "for users with private profiles" do
    test "returns contributions when the viewer is the profile owner" do
      private_user = create(:user, private_profile: true)
      repo = create(:repository, owner: private_user)
      date_range = repo.created_at.beginning_of_month..repo.created_at.end_of_month

      collector = Contribution::Collector.new(
        user: private_user,
        viewer: private_user,
        time_range: date_range,
        contribution_classes: [Contribution::CreatedRepository],
      )

      assert_predicate collector, :any_contribution?
      assert_equal 1, collector.total_repository_contributions
      expected_counts = [[1, repo.id]]
      actual_counts = collector.repository_contribution_counts.map { |c| [c.count, c.id] }
      assert_equal expected_counts, actual_counts
    end

    test "returns an empty collection when the viewer is not the profile owner" do
      private_user = create(:user, private_profile: true)
      private_viewer = create(:user)
      repo = create(:repository, owner: private_user)
      date_range = repo.created_at.beginning_of_month..repo.created_at.end_of_month

      collector = Contribution::Collector.new(
        user: private_user,
        viewer: private_viewer,
        time_range: date_range,
        contribution_classes: [Contribution::CreatedRepository],
      )

      refute_predicate collector, :any_contribution?
      assert_equal 0, collector.total_repository_contributions
      assert_empty collector.repository_contribution_counts
    end

    test "returns an empty collection when the viewer is anonymous" do
      private_user = create(:user, private_profile: true)
      repo = create(:repository, owner: private_user)
      date_range = repo.created_at.beginning_of_month..repo.created_at.end_of_month

      collector = Contribution::Collector.new(
        user: private_user,
        viewer: nil,
        time_range: date_range,
        contribution_classes: [Contribution::CreatedRepository],
      )

      refute_predicate collector, :any_contribution?
      assert_equal 0, collector.total_repository_contributions
      assert_empty collector.repository_contribution_counts
    end
  end
end
