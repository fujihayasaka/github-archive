# typed: true
# frozen_string_literal: true

require "test_helper"

class MetricQueryTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "user")
    @source_repository = create(:repository, owner: @user)
  end

  def force_fixtures_into_current_timespan
    @user.update created_at: Time.current
    @source_repository.update created_at: Time.current
  end

  def make_five_issues
    5.times do create :issue,
      user: @user,
      repository: @source_repository,
      body: "We have an issue."
    end
  end

  context ".build" do
    test "accepts valid query name" do
      %i[issues_created issues_closed pull_requests_created pull_requests_merged
         issue_comments_created pull_request_reviews_created
         repositories_created users_created organizations_created teams_created
      ].each do |name|
        MetricQuery.build(name)
      end
    end

    test "raises when given invalid query name" do
      assert_raises NameError do
        MetricQuery.build(:invalid_metric_name)
      end
    end
  end

  test "with no data all should be zero" do
    freeze_time do
      assert_empty MetricQuery::IssuesCreated.new.all.values.reject(&:zero?)
    end
  end

  test "buckets monthly counts by beginning of day" do
    travel_to Time.zone.local(2004, 11, 24, 12, 0, 0, 0) do
      create(:issue)

      assert_equal Time.zone.local(2004, 11, 24, 0, 0, 0).to_i, MetricQuery::IssuesCreated.new(timespan: MetricTimespan::Month.new).all.keys.first
    end
  end

  test "#previous gives same query with previous timespan" do
    timespan = MetricTimespan::Week.new
    query = MetricQuery::IssuesCreated.new(timespan: timespan)

    assert_instance_of MetricQuery::IssuesCreated, query.previous

    prev_timespan = query.previous.instance_variable_get(:@timespan)
    assert_equal timespan.previous, prev_timespan
  end

  test "#name gives the underscored class name" do
    assert_equal "issue_comments_created", MetricQuery::IssueCommentsCreated.new.name
  end

  context "dogstats instrumentation" do
    test "records cache misses" do
      disable_feature_flag(:metric_query_kv)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      MetricQuery::IssuesCreated.new.cache_get

      assert_equal 1, GitHub.dogstats.increments("metric_query", tags: ["cache:miss", "name:issues_created", "period:week"]).count
    end

    test "enqueues job when there's no stats cached" do
      disable_feature_flag(:metric_query_kv)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      assert_enqueued_with(job: CollectMetricsJob, args: [{}]) do
        MetricQuery::IssuesCreated.new.cache_get
      end

    end

    test "records cache hits" do
      disable_feature_flag(:metric_query_kv)
      freeze_time do
        MetricQuery::IssuesCreated.new.cache_put

        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        MetricQuery::IssuesCreated.new.cache_get

        assert_equal 1, GitHub.dogstats.increments("metric_query", tags: ["cache:hit", "name:issues_created", "period:week"]).count
      end
    end
  end

  context MetricQuery::IssuesCreated do
    test "does not include pull_requests" do
      freeze_time do
        make_five_issues
        create(:pull_request, :disable_disk_access)

        assert_equal 5, MetricQuery::IssuesCreated.call.total
      end
    end

    test "excludes issues from other repository owners" do
      freeze_time do
        make_five_issues
        create(:issue) # no owner

        assert_equal 5, MetricQuery::IssuesCreated.new(owner_id: @user.id).call.total
      end
    end
  end

  context MetricQuery::IssuesClosed do
    test "does not include pull_requests" do
      freeze_time do
        create(:issue)
        create(:issue).close
        create(:pull_request, :disable_disk_access)

        assert_equal 1, MetricQuery::IssuesClosed.call.total
      end
    end

    test "excludes issues from other repository owners" do
      freeze_time do
        issue = create(:issue,
          user: @user,
          repository: @source_repository,
          body: "We have an issue.",
        )
        issue.close

        another_issue = create(:issue)
        another_issue.close

        assert_equal 1, MetricQuery::IssuesClosed.new(owner_id: @user.id).call.total
      end
    end
  end

  context MetricQuery::PullRequestsCreated do
    test "returns all pull requests when no owner_id is passed" do
      freeze_time do
        repo = create(:repository, owner: @user, from_example: :simple)
        issue = create(:issue, user: @user, repository: repo)
        create(:pull_request, user: @user, issue: issue, head_ref: "cr-line-endings")

        another_user = create(:user)
        another_repo = create(:repository, owner: another_user, from_example: :simple)
        another_issue = create(:issue, user: another_user, repository: another_repo)
        create(:pull_request, user: another_user, issue: another_issue, head_ref: "cr-line-endings")

        assert_equal 2, MetricQuery::PullRequestsCreated.new.call.total
      end
    end

    test "excludes pull_requests from other repository owners" do
      freeze_time do
        repo = create(:repository, owner: @user, from_example: :simple)
        issue = create(:issue, user: @user, repository: repo)
        create(:pull_request, user: @user, issue: issue, head_ref: "cr-line-endings")

        another_user = create(:user)
        another_repo = create(:repository, owner: another_user, from_example: :simple)
        another_issue = create(:issue, user: another_user, repository: another_repo)
        create(:pull_request, user: another_user, issue: another_issue, head_ref: "cr-line-endings")

        assert_equal 1, MetricQuery::PullRequestsCreated.new(owner_id: @user.id).call.total
      end
    end
  end

  context MetricQuery::PullRequestsMerged do
    test "returns all merged pull_requests when no owner_id is passed" do
      freeze_time do
        repo = create(:repository, owner: @user, from_example: :simple)
        issue = create(:issue, user: @user, repository: repo)
        pr = create(:pull_request, user: @user, issue: issue, head_ref: "cr-line-endings")
        pr.merge

        another_user = create(:user)
        another_repo = create(:repository, owner: another_user, from_example: :simple)
        another_issue = create(:issue, user: another_user, repository: another_repo)
        another_pr = create(:pull_request, user: another_user, issue: another_issue, head_ref: "cr-line-endings")
        another_pr.merge

        assert_equal 2, MetricQuery::PullRequestsMerged.new.call.total
      end
    end

    test "excludes merged pull_requests from other repository owners" do
      freeze_time do
        repo = create(:repository, owner: @user, from_example: :simple)
        issue = create(:issue, user: @user, repository: repo)
        pr = create(:pull_request, user: @user, issue: issue, head_ref: "cr-line-endings")
        pr.merge

        another_user = create(:user)
        another_repo = create(:repository, owner: another_user, from_example: :simple)
        another_issue = create(:issue, user: another_user, repository: another_repo)
        another_pr = create(:pull_request, user: another_user, issue: another_issue, head_ref: "cr-line-endings")
        another_pr.merge

        assert_equal 1, MetricQuery::PullRequestsMerged.new(owner_id: @user.id).call.total
      end
    end
  end

  context MetricQuery::PullRequestReviewsCreated do
    test "returns all pull_request_reviews when no owner_id is passed" do
      freeze_time do
        repo = create(:repository, owner: @user, from_example: :simple)
        issue = create(:issue, user: @user, repository: repo)
        pr = create(:pull_request, user: @user, issue: issue, head_ref: "cr-line-endings")
        create(:pull_request_review, pull_request: pr)

        another_user = create(:user)
        another_repo = create(:repository, owner: another_user, from_example: :simple)
        another_issue = create(:issue, user: another_user, repository: another_repo)
        another_pr = create(:pull_request, user: another_user, issue: another_issue, head_ref: "cr-line-endings")
        create(:pull_request_review, pull_request: another_pr)

        assert_equal 2, MetricQuery::PullRequestReviewsCreated.new.call.total
      end
    end

    test "excludes pull_request_reviews from other repository owners" do
      freeze_time do
        repo = create(:repository, owner: @user, from_example: :simple)
        issue = create(:issue, user: @user, repository: repo)
        pr = create(:pull_request, user: @user, issue: issue, head_ref: "cr-line-endings")
        create(:pull_request_review, pull_request: pr)

        another_user = create(:user)
        another_repo = create(:repository, owner: another_user, from_example: :simple)
        another_issue = create(:issue, user: another_user, repository: another_repo)
        another_pr = create(:pull_request, user: another_user, issue: another_issue, head_ref: "cr-line-endings")
        create(:pull_request_review, pull_request: another_pr)

        assert_equal 1, MetricQuery::PullRequestReviewsCreated.new(owner_id: @user.id).call.total
      end
    end
  end

  context MetricQuery::RepositoriesCreated do
    test "returns all repositories from when no owner_id is passed" do
      freeze_time do
        force_fixtures_into_current_timespan

        assert_equal 1, MetricQuery::RepositoriesCreated.new.call.total
      end
    end

    test "excludes repositories from other owners when owner_id is passed" do
      freeze_time do
        force_fixtures_into_current_timespan
        create(:repository)

        assert_equal 1, MetricQuery::RepositoriesCreated.new(owner_id: @user.id).call.total
      end
    end
  end

  context MetricQuery::IssueCommentsCreated do
    test "excludes issue comments from other repository owners when owner_id is passed" do
      freeze_time do
        issue = create(:issue, user: @user, repository: @source_repository)
        create(:issue_comment, issue: issue)
        create(:issue_comment)


        assert_equal 1, MetricQuery::IssueCommentsCreated.new(owner_id: @user.id).call.total
      end
    end
  end

  context MetricQuery::PullRequestCommentsCreated do
    test "excludes pull request comments from other repository owners when owner_id is passed" do
      freeze_time do
        repo = create(:repository, owner: @user, from_example: :simple)
        issue = create(:issue, user: @user, repository: repo)
        pr = create(:pull_request, user: @user, issue: issue, head_ref: "cr-line-endings")

        create(:issue_comment, issue: issue)
        create(:issue_comment)

        assert_equal 1, MetricQuery::PullRequestCommentsCreated.new(owner_id: @user.id).call.total
      end
    end
  end

  context MetricQuery::TeamsCreated do
    test "returns all teams when no owner_id is passed" do
      freeze_time do
        create(:team)

        assert_equal 1, MetricQuery::TeamsCreated.new.call.total
      end
    end

    test "excludes teams from other orgs when owner_id is passed" do
      freeze_time do
        org = create(:organization)
        create(:team, organization: org)
        create(:team)

        assert_equal 1, MetricQuery::TeamsCreated.new(owner_id: org.id).call.total
      end
    end
  end

  context MetricQuery::UsersCreated do
    test "it works" do
      freeze_time do
        force_fixtures_into_current_timespan

        assert_equal 1, MetricQuery::UsersCreated.new.call.total
      end
    end
  end

  context MetricQuery::OrganizationsCreated do
    test "it works" do
      freeze_time do
        create(:organization)

        assert_equal 1, MetricQuery::OrganizationsCreated.new.call.total
      end
    end
  end

  context MetricQuery::CommitsContributed do
    test "it returns all commit contributions when no owner_id is passed" do
      freeze_time do
        owner_repo = create(:repository, owner: @user)
        create(:commit_contribution, repository: owner_repo, committed_date: Time.zone.today)

        another_repo = create(:repository)
        create(:commit_contribution, repository: another_repo, committed_date: Time.zone.today)

        assert_equal 10, MetricQuery::CommitsContributed.new.call.total
      end
    end

    test "it excludes commit contributions from repos outside the org" do
      freeze_time do
        owner_repo = create(:repository, owner: @user)
        create(:commit_contribution, repository: owner_repo, committed_date: Time.zone.today)

        another_repo = create(:repository)
        create(:commit_contribution, repository: another_repo, committed_date: Time.zone.today)

        assert_equal 5, MetricQuery::CommitsContributed.new(owner_id: @user.id).call.total
      end
    end
  end
end
