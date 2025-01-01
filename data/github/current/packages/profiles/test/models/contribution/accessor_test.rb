# typed: false
# frozen_string_literal: true

require "test_helper"

class ContributionAccessorTest < GitHub::TestCase
  fixtures do
    @user = create(:user, plan: "medium")
  end

  def mock_contribution
    Class.new(Contribution) do
      def self.name
        "MockContribution"
      end

      def associated_subject
        subject
      end

      def occurred_at
        Time.now
      end
    end
  end

  def mock_subject
    create(:repository)
  end

  setup do
    reset_cache

    @user = create(:user)
  end

  def accessor_for(
    user: @user,
    viewer: nil,
    contribution_classes:,
    date_range: 1.month.ago.to_date..Date.tomorrow,
    use_contribution_fetchers: false
  )
    Contribution::Accessor.new(
      user: user,
      viewer: viewer,
      contribution_classes: contribution_classes,
      date_range: date_range,
      organization_id: nil,
      skip_restricted: false,
      excluded_organization_ids: [],
      lightweight: true,
      use_contribution_fetchers: use_contribution_fetchers,
    )
  end

  def create_commit(user, date: Time.zone.today)
    repository = create(:repository)
    repository.add_member(user)
    create(:commit_contribution, :with_summaries, user: user, repository: repository, committed_date: date)
  end

  def create_pull_request(options)
    repo = options.delete(:repo)
    user = options.fetch(:user)
    issue = options.fetch(:issue, create(:issue, repository: repo, user: user))
    create(:pull_request, options.reverse_merge(
      repository: repo,
      base_repository: repo,
      base_user: user,
      base_ref: "master",
      head_repository: repo,
      head_user: user,
      issue: issue,
    ))
  end

  def create_timezone_aware_pull_request(user, created_at:, contributed_at:)
    repo = create(:repository, owner: user, from_example: :rebase_pull_request)
    issue = user.issues.create!(repository: repo,
      title: "Issue from #{created_at}",
      created_at: created_at,
      contributed_at: contributed_at,
    )
    create_pull_request(
      user: user,
      repo: repo,
      head_ref: "contrib",
      issue: issue,
      created_at: created_at,
      contributed_at: contributed_at,
    )
  end

  test "sorts commits by committed_date DESC" do
    new_commit = create_commit(@user, date: Time.zone.now)
    old_commit = create_commit(@user, date: 1.day.ago)
    very_old_commit = create_commit(@user, date: 2.days.ago)

    accessor = accessor_for(contribution_classes: [Contribution::CreatedCommit])
    results = accessor.visible_contributions_of(Contribution::CreatedCommit)

    expected = [new_commit, old_commit, very_old_commit]
    expected_attributes = expected.map { |c| c.slice(:user_id, :repository_id, :commit_count, :committed_date) }

    actual = results.map(&:commit_contribution)
    actual_attributes = actual.map { |c| c.slice(:user_id, :repository_id, :commit_count, :committed_date) }

    assert_equal expected_attributes, actual_attributes
  end

  test "sorts issues by contributed_at DESC" do
    # issue with lower created_at, id, higher contributed_at
    new_issue = Timecop.freeze(1.week.ago) { create(:issue, user: @user) }
    new_issue.contributed_at = 1.day.ago
    new_issue.save!

    # issue with higher created_at, id, lower contributed_at
    old_issue = Timecop.freeze(1.day.ago) { create(:issue, user: @user) }
    old_issue.contributed_at = 1.week.ago
    old_issue.save!

    assert old_issue.id > new_issue.id
    assert old_issue.created_at > new_issue.created_at
    assert old_issue.contributed_at < new_issue.contributed_at

    accessor = accessor_for(contribution_classes: [Contribution::CreatedIssue])
    results = accessor.visible_contributions_of(Contribution::CreatedIssue)

    assert_equal 2, results.size
    assert_equal [new_issue, old_issue], results.map(&:issue)
  end

  # Using http://everytimezone.com/#2014-5-15 is helpful to understand these
  # timezone tests.
  test "sorts issues by timezone aware contributed_at instead of created_at" do
    user = create(:user)

    from = Time.utc(2014, 5, 15).beginning_of_day
    to = Time.utc(2014, 5, 22).end_of_day

    valid_issues = []

    created_at = from # 2015-5-15 in UTC
    contributed_at = created_at.in_time_zone("Hawaii") # 2014-5-14 in Hawaii
    # invalid because contributed_at is not in the time range, although created_at is
    create(:issue, user: user, created_at: created_at, contributed_at: contributed_at)

    created_at = from.yesterday.end_of_day # 2014-5-14 in UTC
    contributed_at = created_at.in_time_zone("Auckland") # 2014-5-15 in Auckland
    # valid because contributed_at is in the time range, although created_at is not
    valid_issues << create(:issue, user: user, created_at: created_at,
                                      contributed_at: contributed_at)

    created_at = to.tomorrow.beginning_of_day # 2014-5-23 in UTC
    contributed_at = created_at.in_time_zone("Hawaii") # 2014-5-22 in Hawaii
    # valid because contributed_at is in the time range, although created_at is not
    valid_issues << create(:issue, user: user, created_at: created_at,
                                      contributed_at: contributed_at)

    created_at = to # 2014-5-22 in UTC
    contributed_at = created_at.in_time_zone("Auckland") # 2014-5-23 in Auckland
    # invalid because contributed_at is not in the time range, although created_at is
    create(:issue, user: user, created_at: created_at, contributed_at: contributed_at)

    accessor = accessor_for(user: user, contribution_classes: [Contribution::CreatedIssue], date_range: from.to_date..to.to_date)
    results = accessor.visible_contributions_of(Contribution::CreatedIssue)

    assert_same_elements valid_issues, results.map(&:issue)
  end

  test "includes issue with contributed_at when the accessor only spans one day" do
    user = create(:user)

    from = Time.utc(2014, 5, 15).beginning_of_day
    to = Time.utc(2014, 5, 15).end_of_day

    valid_issues = []

    created_at = from.yesterday.end_of_day # 2014-5-14 in UTC
    contributed_at = created_at.in_time_zone("Auckland")  # 2014-5-15 in Auckland

    # valid because contributed_at is in the date range
    valid_issues << create(:issue, user: user, created_at: created_at,
                                      contributed_at: contributed_at)

    created_at = from # 2014-5-15 in UTC
    contributed_at = created_at.in_time_zone("Hawaii") # 2014-5-14 in Hawaii
    # invalid because contributed_at is not within the date range
    create(:issue, user: user, created_at: created_at, contributed_at: contributed_at)

    accessor = accessor_for(user: user, contribution_classes: [Contribution::CreatedIssue], date_range: from.to_date..to.to_date)
    results = accessor.visible_contributions_of(Contribution::CreatedIssue)

    assert_same_elements valid_issues, results.map(&:issue)
  end

  test "sorts issue comments by created_at DESC" do
    repo = create(:repository, owner: @user)
    issue = create(:issue, repository: repo, user: @user)

    new_contribution = create(:issue_comment, user: @user, issue: issue, created_at: Time.zone.now)
    old_contribution = create(:issue_comment, user: @user, issue: issue, created_at: 1.day.ago)
    very_old_contribution = create(:issue_comment, user: @user, issue: issue, created_at: 2.days.ago)

    accessor = accessor_for(contribution_classes: [Contribution::CreatedIssueComment])
    results = accessor.visible_contributions_of(Contribution::CreatedIssueComment)

    assert_equal [new_contribution, old_contribution, very_old_contribution], results.map(&:comment)
  end

  test "sorts pull requests by contributed_at DESC" do
    new_repo = create(:repository, owner: @user, name: "new-repo", from_example: :pull_request_fork)
    new_pull = create_pull_request(user: @user, repo: new_repo, head_ref: "ahead")

    old_repo = create(:repository, owner: @user, name: "old-repo", from_example: :pull_request_fork)
    old_pull = Timecop.freeze(1.week.ago) do
      create_pull_request(user: @user, repo: old_repo, head_ref: "ahead")
    end

    accessor = accessor_for(contribution_classes: [Contribution::CreatedPullRequest])
    results = accessor.visible_contributions_of(Contribution::CreatedPullRequest)

    assert_equal [new_pull, old_pull], results.map(&:pull_request)
  end

  # Using http://everytimezone.com/#2014-5-15 is helpful to understand these
  # timezone tests.
  test "sorts pull requests by timezone aware contributed_at instead of created_at" do
    user = create(:user)

    from = Time.utc(2014, 5, 15).beginning_of_day
    to = Time.utc(2014, 5, 22).end_of_day

    valid_pulls = []

    created_at = from # 2015-5-15 in UTC
    contributed_at = created_at.in_time_zone("Hawaii") # 2014-5-14 in Hawaii
    # invalid because contributed_at is not in the time range, although created_at is
    create_timezone_aware_pull_request(user, created_at: created_at,
                                              contributed_at: contributed_at)

    created_at = from.yesterday.end_of_day # 2014-5-14 in UTC
    contributed_at = created_at.in_time_zone("Auckland") # 2014-5-15 in Auckland
    # valid because contributed_at is in the time range, although created_at is not
    valid_pulls << create_timezone_aware_pull_request(user, created_at: created_at,
                                                            contributed_at: contributed_at)

    created_at = to.tomorrow.beginning_of_day # 2014-5-23 in UTC
    contributed_at = created_at.in_time_zone("Hawaii") # 2014-5-22 in Hawaii
    # valid because contributed_at is in the time range, although created_at is not
    valid_pulls << create_timezone_aware_pull_request(user, created_at: created_at,
                                                            contributed_at: contributed_at)

    created_at = to # 2014-5-22 in UTC
    contributed_at = created_at.in_time_zone("Auckland") # 2014-5-23 in Auckland
    # invalid because contributed_at is not in the time range, although created_at is
    create_timezone_aware_pull_request(user, created_at: created_at,
                                              contributed_at: contributed_at)

    accessor = accessor_for(user: user, contribution_classes: [Contribution::CreatedPullRequest], date_range: from.to_date..to.to_date)
    results = accessor.visible_contributions_of(Contribution::CreatedPullRequest)

    assert_same_elements valid_pulls, results.map(&:pull_request)
  end

  test "uses CreatePullRequest.subjects_for when not using contribution fetchers" do
    accessor = accessor_for(contribution_classes: [Contribution::CreatedPullRequest], use_contribution_fetchers: false)

    Contribution::CreatedPullRequest.expects(:subjects_for).once.returns([])
    Contribution::Fetcher::CreatedPullRequest.expects(:new).never

    accessor.visible_contributions_of(Contribution::CreatedPullRequest)
  end

  test "uses Fetchers::CreatedPullRequest#subjects_in_date_range when using contribution fetchers" do
    test_fetcher = stub
    Contribution::Fetcher::CreatedPullRequest.stubs(:new).returns(test_fetcher)
    accessor = accessor_for(contribution_classes: [Contribution::CreatedPullRequest], use_contribution_fetchers: true)

    Contribution::CreatedPullRequest.expects(:subjects_for).never
    test_fetcher.expects(:subjects_in_date_range).once.returns([])

    accessor.visible_contributions_of(Contribution::CreatedPullRequest)
  end

  test "sorts pull request reviews by submitted_at DESC" do
    new_review, old_review = nil, nil

    Timecop.freeze(1.day.ago) do
      repo = create(:repository, from_example: :encodings)
      pr = create(:pull_request, repository: repo, base_ref: "empty-branch", head_ref: "master", user: @user)
      new_review = create(:pull_request_review, user: @user, pull_request: pr)
      new_review.comment!
    end

    Timecop.freeze(1.week.ago) do
      repo = create(:repository, from_example: :encodings)
      pr = create(:pull_request, repository: repo, base_ref: "empty-branch", head_ref: "master", user: @user)
      old_review = create(:pull_request_review, user: @user, pull_request: pr)
      old_review.comment!
    end

    accessor = accessor_for(contribution_classes: [Contribution::CreatedPullRequestReview])
    results = accessor.visible_contributions_of(Contribution::CreatedPullRequestReview)

    assert_equal [new_review, old_review], results.map(&:pull_request_review)
  end

  context "for regular viewers", skip_enterprise: true do
    test "removes pull request reviews for pull requests authored by spammy users" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        valid_pull_request_review = travel_to(1.day.ago) do
          repo = create(:repository, from_example: :encodings)
          pr = create(
            :pull_request,
            repository: repo,
            base_ref: "empty-branch",
            head_ref: "master",
            user: create(:verified_user),
          )
          create(:pull_request_review, user: @user, pull_request: pr).tap { |review| review.comment! }
        end

        invalid_pull_request_review = travel_to(1.day.ago) do
          repo = create(:repository, from_example: :encodings)
          user_that_will_be_spammy = create(:verified_user)
          pr = create(
            :pull_request,
            repository: repo,
            base_ref: "empty-branch",
            head_ref: "master",
            user: user_that_will_be_spammy,
          )
          review = create(:pull_request_review, user: @user, pull_request: pr)
          review.comment!
          user_that_will_be_spammy.mark_as_spammy
          review
        end

        accessor = accessor_for(
          viewer: create(:verified_user),
          contribution_classes: [Contribution::CreatedPullRequestReview],
        )
        results = accessor.visible_contributions_of(Contribution::CreatedPullRequestReview)

        assert_includes results.map(&:pull_request_review), valid_pull_request_review
        refute_includes results.map(&:pull_request_review), invalid_pull_request_review
      end
    end
  end

  context "for staff viewers" do
    test "does not remove pull request reviews for pull requests authored by spammy users" do
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
        valid_pull_request_review = travel_to(1.day.ago) do
          repo = create(:repository, from_example: :encodings)
          pr = create(
            :pull_request,
            repository: repo,
            base_ref: "empty-branch",
            head_ref: "master",
            user: create(:verified_user),
          )
          create(:pull_request_review, user: @user, pull_request: pr).tap { |review| review.comment! }
        end

        invalid_pull_request_review = travel_to(1.day.ago) do
          repo = create(:repository, from_example: :encodings)
          user_that_will_be_spammy = create(:verified_user)
          pr = create(
            :pull_request,
            repository: repo,
            base_ref: "empty-branch",
            head_ref: "master",
            user: user_that_will_be_spammy,
          )
          review = create(:pull_request_review, user: @user, pull_request: pr)
          review.comment!
          user_that_will_be_spammy.mark_as_spammy
          review
        end

        accessor = accessor_for(
          viewer: create(:staff_admin_user),
          contribution_classes: [Contribution::CreatedPullRequestReview],
        )
        results = accessor.visible_contributions_of(Contribution::CreatedPullRequestReview)

        assert_includes results.map(&:pull_request_review), valid_pull_request_review
        assert_includes results.map(&:pull_request_review), invalid_pull_request_review
      end
    end
  end

  test "sorts repositories by created_at DESC" do
    new_repo = create(:repository, owner: @user, created_at: 1.day.ago)
    old_repo = create(:repository, owner: @user, created_at: 1.week.ago)

    accessor = accessor_for(contribution_classes: [Contribution::CreatedRepository])
    results = accessor.visible_contributions_of(Contribution::CreatedRepository)

    assert_equal [new_repo, old_repo], results.map(&:repository)
  end

  context "#visible_contributions_of" do
    test "only returns visible contributions of the specified type" do
      user = create(:user)
      date_range = Date.yesterday..Date.tomorrow

      contribution_class = mock_contribution
      subjects = [mock_subject, mock_subject]
      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns(subjects)

      other_type = Class.new(mock_contribution)
      other_subjects = [mock_subject, mock_subject]
      other_type.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns(other_subjects)

      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(false)

      accessor = Contribution::Accessor.new(
        user: user,
        viewer: nil,
        date_range: date_range,
        contribution_classes: [contribution_class, other_type],
        organization_id: nil,
        skip_restricted: false,
        lightweight: true,
      )

      visible_contributions = accessor.visible_contributions_of(contribution_class)
      assert_same_elements subjects, visible_contributions.map(&:associated_subject)

      visible_other_contributions = accessor.visible_contributions_of(other_type)
      assert_same_elements other_subjects, visible_other_contributions.map(&:associated_subject)
    end

    test "excludes contributions associated with an orphan repository" do
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

      accessor = Contribution::Accessor.new(
        user: user,
        viewer: nil,
        date_range: date_range,
        contribution_classes: [contribution_class],
        organization_id: nil,
        skip_restricted: false,
        lightweight: true,
      )

      assert_equal [repo], accessor.visible_contributions_of(contribution_class).map(&:associated_subject)

      repo.owner.delete # do not trigger callbacks

      accessor = Contribution::Accessor.new(
        user: user,
        viewer: nil,
        date_range: date_range,
        contribution_classes: [contribution_class],
        organization_id: nil,
        skip_restricted: false,
        lightweight: true,
      )

      assert_empty accessor.visible_contributions_of(contribution_class)
    end

    test "excludes contributions associated with a repository marked for deletion" do
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

      accessor = Contribution::Accessor.new(
        user: user,
        viewer: nil,
        date_range: date_range,
        contribution_classes: [contribution_class],
        organization_id: nil,
        skip_restricted: false,
        lightweight: true,
      )

      assert_equal [repo], accessor.visible_contributions_of(contribution_class).map(&:associated_subject)

      repo.update(active: nil)

      accessor = Contribution::Accessor.new(
        user: user,
        viewer: nil,
        date_range: date_range,
        contribution_classes: [contribution_class],
        organization_id: nil,
        skip_restricted: false,
        lightweight: true,
      )

      assert_empty accessor.visible_contributions_of(contribution_class)
    end

    test "only includes contributions that match the organization_id" do
      user = create(:user)
      org = create(:organization)
      org_repo = create(:repository, owner: org)
      repo = create(:repository)

      date_range = Date.yesterday..Date.tomorrow

      contribution_class = Class.new(mock_contribution) do
        def occurred_at
          subject.created_at
        end

        def organization_id
          subject.organization_id
        end
      end
      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: org.id,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([org_repo, repo])

      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(false)

      accessor = Contribution::Accessor.new(
        user: user,
        viewer: nil,
        date_range: date_range,
        contribution_classes: [contribution_class],
        organization_id: org.id,
        skip_restricted: false,
        lightweight: true,
      )

      assert_equal [org_repo], accessor.visible_contributions_of(contribution_class).map(&:associated_subject)
    end

    test "returns all contributions when organization_id is nil" do
      user = create(:user)
      org = create(:organization)
      org_repo = create(:repository, owner: org)
      repo = create(:repository)

      date_range = Date.yesterday..Date.tomorrow

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
      ).returns([org_repo, repo])

      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(false)

      accessor = Contribution::Accessor.new(
        user: user,
        viewer: nil,
        date_range: date_range,
        contribution_classes: [contribution_class],
        organization_id: nil,
        skip_restricted: false,
        lightweight: true,
      )

      assert_same_elements [org_repo, repo], accessor.visible_contributions_of(contribution_class).map(&:associated_subject)
    end

    test "excludes restricted contributions when skip_restricted is true" do
      user = create(:user)
      repo = create(:repository, owner: user)

      date_range = Date.yesterday..Date.tomorrow

      contribution_class = Class.new(mock_contribution) do
        def occurred_at
          subject.created_at
        end

        def organization_id
          subject.organization_id
        end
      end
      contribution_class.stubs(:subjects_for).with(
        user,
        date_range: date_range,
        organization_id: nil,
        excluded_organization_ids: [],
        lightweight: true,
      ).returns([repo])

      Contribution::VisibilityChecker.any_instance.stubs(:restricted?).returns(true)

      accessor = Contribution::Accessor.new(
        user: user,
        viewer: nil,
        date_range: date_range,
        contribution_classes: [contribution_class],
        organization_id: nil,
        skip_restricted: true,
        lightweight: true,
      )

      assert_empty accessor.visible_contributions_of(contribution_class).map(&:subject)
    end
  end

  context "#counts_by_class_name" do
    test "doesn't return nil if there is cached data that doesn't include counts_by_class_name" do
      repo = create(:repository, owner: @user)
      accessor = Contribution::Accessor.new(
        user: @user,
        viewer: nil,
        date_range: Date.yesterday..Date.tomorrow,
        contribution_classes: [Contribution::CreatedRepository],
        organization_id: nil,
        skip_restricted: true,
        lightweight: true,
      )

      # Set up cache without `counts_by_class_name` key
      stubbed_cache = stub("Cache", get: { visible_counts_by_repository_id: {} }, set: nil)
      Contribution::Accessor::Cache.expects(:new).returns(stubbed_cache)

      refute_nil accessor.counts_by_class_name

      expected_counts = { "Contribution::CreatedRepository" => 1 }
      assert_equal expected_counts, accessor.counts_by_class_name
    end
  end

  context "#counts_by_day" do
    test "doesn't return nil if there is cached data that doesn't include counts_by_day" do
      repo = create(:repository, owner: @user)
      accessor = Contribution::Accessor.new(
        user: @user,
        viewer: nil,
        date_range: Date.yesterday..Date.tomorrow,
        contribution_classes: [Contribution::CreatedRepository],
        organization_id: nil,
        skip_restricted: true,
        lightweight: true,
      )

      # Set up cache without `counts_by_class_name` key
      stubbed_cache = stub("Cache", get: { visible_counts_by_repository_id: {} }, set: nil)
      Contribution::Accessor::Cache.expects(:new).returns(stubbed_cache)

      refute_nil accessor.counts_by_day

      expected_counts = { repo.created_at.to_date => 1 }
      assert_equal expected_counts, accessor.counts_by_day
    end
  end

  context "#visible_counts_by_repository_id" do
    test "caches results" do
      with_cache_enabled do
        repo = create(:repository, owner: @user)

        arguments = {
          user: @user,
          viewer: nil,
          date_range: Date.yesterday..Date.tomorrow,
          contribution_classes: [Contribution::CreatedRepository],
          organization_id: nil,
          skip_restricted: true,
          lightweight: true,
        }

        # Warm the cache and verify our assumptions
        accessor = Contribution::Accessor.new(**arguments)
        assert_equal({ repo.id => 1 }, accessor.visible_counts_by_repository_id)

        # Call again and make sure there is no fetch, but same results
        Contribution::Accessor.any_instance.expects(:fetch_all_contributions).times(0)
        cached_accessor = Contribution::Accessor.new(**arguments)
        assert_equal({ repo.id => 1 }, cached_accessor.visible_counts_by_repository_id)
      end
    end

    test "filters out removed repository ids" do
      with_cache_enabled do
        repo = create(:repository, owner: @user)

        arguments = {
          user: @user,
          viewer: nil,
          date_range: Date.yesterday..Date.tomorrow,
          contribution_classes: [Contribution::CreatedRepository],
          organization_id: nil,
          skip_restricted: true,
          lightweight: true,
        }

        # Load accessor to warm the cache, and check our assumptions
        accessor = Contribution::Accessor.new(**arguments)
        assert_equal({ repo.id => 1 }, accessor.visible_counts_by_repository_id)

        # Remove the repository entirely, but without callbacks that would reset contributions data
        repo.delete

        # Warm cache, no contributions should be fetched
        Contribution::Accessor.any_instance.expects(:fetch_all_contributions).times(0)
        cached_accessor = Contribution::Accessor.new(**arguments)

        # Make sure the repository id has been filtered out
        assert_empty cached_accessor.visible_counts_by_repository_id
      end
    end

    test "filters out contributions which are no longer valid" do
      with_cache_enabled do
        issue = create(:issue, user: @user)

        arguments = {
          user: @user,
          viewer: nil,
          date_range: Date.yesterday..Date.tomorrow,
          contribution_classes: [Contribution::CreatedIssue],
          organization_id: nil,
          skip_restricted: true,
          lightweight: true,
        }

        # Load accessor to warm the cache, and check our assumptions
        accessor = Contribution::Accessor.new(**arguments)
        assert_equal({ issue.repository.id => 1 }, accessor.visible_counts_by_repository_id)

        # Currently the only way that visibility checker will return invalid
        # for a subject is if the repository has been orphaned which would
        # be also filtered out if the repository has been removed. So this
        # test is a little odd but we're purposely checking that if `valid?`
        # returns `false` we filter the repository even if it hasn't been deleted.
        # Orphan the contribution
        Contribution::VisibilityChecker.any_instance.expects(:valid_repository_ids).returns([])

        # Warm cache, no contributions should be fetched
        Contribution::Accessor.any_instance.expects(:fetch_all_contributions).times(0)
        cached_accessor = Contribution::Accessor.new(**arguments)

        # Make sure the repository id has been filtered out
        assert_empty cached_accessor.visible_counts_by_repository_id
      end
    end

    test "filters out contributions which have become restricted if skip_restricted is true" do
      with_cache_enabled do
        repo = create(:repository, owner: @user)

        arguments = {
          user: @user,
          viewer: nil,
          date_range: Date.yesterday..Date.tomorrow,
          contribution_classes: [Contribution::CreatedRepository],
          organization_id: nil,
          skip_restricted: true,
          lightweight: true,
        }

        # Load accessor to warm the cache, and check our assumptions
        accessor = Contribution::Accessor.new(**arguments)
        assert_equal({ repo.id => 1 }, accessor.visible_counts_by_repository_id)

        # Repository becomes private
        repo.private = true
        repo.save!

        # Warm cache, no contributions should be fetched
        Contribution::Accessor.any_instance.expects(:fetch_all_contributions).times(0)
        cached_accessor = Contribution::Accessor.new(**arguments)

        # Make sure the repository id has been filtered out
        assert_empty cached_accessor.visible_counts_by_repository_id
      end
    end

    test "filters out contributions which have become restricted even if skip_restricted is false" do
      with_cache_enabled do
        repo = create(:repository, owner: @user)

        arguments = {
          user: @user,
          viewer: nil,
          date_range: Date.yesterday..Date.tomorrow,
          contribution_classes: [Contribution::CreatedRepository],
          organization_id: nil,
          skip_restricted: false,
          excluded_organization_ids: [],
          lightweight: true,
        }

        # Load accessor to warm the cache, and check our assumptions
        accessor = Contribution::Accessor.new(**arguments)
        assert_equal({ repo.id => 1 }, accessor.visible_counts_by_repository_id)

        # Repository becomes private
        repo.private = true
        repo.save!

        # Warm cache, no contributions should be fetched
        Contribution::Accessor.any_instance.expects(:fetch_all_contributions).times(0)
        cached_accessor = Contribution::Accessor.new(**arguments)

        # Make sure the repository id has been filtered out
        assert_empty cached_accessor.visible_counts_by_repository_id
      end
    end
  end

  context "caching" do
    # Ensure we don't make unexpected changes to our cache key
    test "passes all parameters as inputs for the cache key" do
      user = create(:user)
      viewer = create(:user)
      date_range = Date.yesterday..Date.tomorrow
      organization_id = 123

      args = {
        user: user,
        viewer: viewer,
        date_range: date_range,
        contribution_classes: [Contribution::CreatedRepository, Contribution::CreatedIssue],
        organization_id: organization_id,
        skip_restricted: false,
        excluded_organization_ids: [],
        lightweight: true,
      }

      accessor = Contribution::Accessor.new(**args)
      Contribution::Accessor::Cache.expects(:new).with(equals(args)).returns(stub(get: nil, set: nil))

      # Call a method to trigger a cache lookup
      accessor.visible_counts_by_repository_id
    end

    # Hello future potentially-frustrated developer! This test is here to make
    # sure that when you're making changes to the signature of `initialize`
    # on `Accessor`, you're also considering the impact of your changes on
    # the `cache_key`. Generally speaking, changes to the initializer will
    # also require an addition or modification to the `key_parts` passed to
    # `Accessor::Cache.new`.
    #
    # Once you're confident in your changes, just update this test accordingly
    # and be on your way. Safe travels!
    test "lints for new initializer arguments" do
      parameters = Contribution::Accessor.instance_method(:initialize).parameters.map(&:second)

      assert_same_elements [
        :user, :viewer, :contribution_classes, :date_range, :organization_id,
        :skip_restricted, :excluded_organization_ids, :lightweight,
        :use_contribution_fetchers
      ], parameters
    end
  end

  context "cache key paranoia tests" do
    test "does not re-use cache between viewers for the otherwise same accessor" do
      with_cache_enabled do
        user = create(:user)

        viewers = [*create_pair(:user), nil]

        viewers.each do |viewer|
          accessor = Contribution::Accessor.new(
            user: user,
            viewer: viewer,
            date_range: Date.yesterday..Date.tomorrow,
            contribution_classes: [Contribution::CreatedIssue],
            organization_id: nil,
            skip_restricted: true,
            excluded_organization_ids: [],
            lightweight: true,
          )

          Contribution::CreatedIssue.expects(:subjects_for).returns([])
          accessor.visible_counts_by_repository_id
        end
      end
    end

    test "does not re-use cache between users for the otherwise same accessor" do
      with_cache_enabled do
        users = create_pair(:user)

        users.each do |user|
          accessor = Contribution::Accessor.new(
            user: user,
            viewer: nil,
            date_range: Date.yesterday..Date.tomorrow,
            contribution_classes: [Contribution::CreatedIssue],
            organization_id: nil,
            skip_restricted: true,
            excluded_organization_ids: [],
            lightweight: true,
          )

          Contribution::CreatedIssue.expects(:subjects_for).returns([])
          accessor.visible_counts_by_repository_id
        end
      end
    end

    test "does not re-use cache when switching skip_restricted" do
      with_cache_enabled do
        user = create(:user)

        [false, true].each do |value|
          accessor = Contribution::Accessor.new(
            user: user,
            viewer: nil,
            date_range: Date.yesterday..Date.tomorrow,
            contribution_classes: [Contribution::CreatedIssue],
            organization_id: nil,
            skip_restricted: value,
            excluded_organization_ids: [],
            lightweight: true,
          )

          Contribution::CreatedIssue.expects(:subjects_for).returns([])
          accessor.visible_counts_by_repository_id
        end
      end
    end
  end
end
