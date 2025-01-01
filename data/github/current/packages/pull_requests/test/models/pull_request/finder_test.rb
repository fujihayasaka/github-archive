# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestFilteringTest < GitHub::TestCase
  fixtures do
    @source = create(:repository, from_example: :pull_request_source)
    @owner  = @source.owner

    @forker = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @user = create(:user)
    @other_fork = create(:fork_repository, forker: @user, fork_repo: @source, from_example: :pull_request_fork)

    @open_pull = PullRequest.create_for! @source,
      user: @forker,
      base: "#{@owner.login}:master",
      head: "#{@forker.login}:topic",
      title: "test cross-repo open PR",
      body: "test PR"

    topic_ref = @fork.heads.find("topic")
    ref       = @fork.heads.create("topic-2", topic_ref.target_oid, @forker)
    @closed_pull = PullRequest.create_for! @source,
      user: @forker,
      base: "#{@owner.login}:master",
      head: "#{@forker.login}:topic-2",
      title: "test cross-repo closed PR",
      body: "test PR"
    @closed_pull.close(@owner)

    ref = @fork.heads.create("to_get_a_merge", topic_ref.target_oid, @forker)
    ref = @fork.heads.create("to_be_merged",   topic_ref.target_oid, @forker)
    metadata = { message: "test commit", committer: @forker }
    ref.append_commit(metadata, @forker)
    @merged_pull = PullRequest.create_for! @fork,
      user: @forker,
      base: "to_get_a_merge",
      head: "to_be_merged",
      title: "test same-repo merged PR",
      body: "test PR"
    @merged_pull.merge

    @other_pull = PullRequest.create_for! @source,
      user: @user,
      base: "#{@owner.login}:master",
      head: "#{@user.login}:topic",
      title: "test other cross-repo open PR",
      body: "test PR"
  end

  test "a closed pull request should not bubble to the top of the recently \
        updated list when the head branch is pushed to" do
    # just need 2 closed PRs. @closed_pull is weird and messes us up.
    @closed_pull.destroy
    pulls = [@open_pull, @other_pull]
    pulls.each { |pull|  pull.close(@owner) }

    # set the timestamps manually so they don't end up being the same
    Timecop.freeze(1.week.ago)  { pulls[0].update_attribute(:created_at, Time.now) }
    Timecop.freeze(1.month.ago) { pulls[1].update_attribute(:created_at, Time.now) }

    result = @source.pull_requests.filtered_and_ordered(
      state: "closed",
      sort: "updated",
      direction: "desc")
    assert_equal pulls, result

    oldest_pr = result.last
    ref = oldest_pr.head_repository.heads.find(oldest_pr.head_ref)

    # "push" to it
    metadata = { message: "test commit", committer: oldest_pr.head_repository.owner }
    ref.append_commit(metadata, oldest_pr.head_repository.owner) do |files|
      files.add("README", "blah blah blah")
    end

    result = @source.pull_requests.filtered_and_ordered(
      state: "closed",
      sort: "updated",
      direction: "desc")
    assert_equal pulls, result
  end

  test "can fetch only open pull requests" do
    expected = [@open_pull, @other_pull]
    assert_same_elements expected, PullRequest.open_pulls.to_a
  end

  test "can fetch only closed pull requests" do
    expected = [@closed_pull, @merged_pull]
    assert_same_elements expected, PullRequest.closed_pulls.to_a
  end

  test "can fetch only pull requests for a specific user" do
    expected = [@other_pull]
    assert_same_elements expected, PullRequest.for_user(@user)
    expected = [@open_pull, @closed_pull, @merged_pull]
    assert_same_elements expected, PullRequest.for_user(@forker)
  end

  context "fetching pull requests ordered by creation time" do
    test "can fetch most recent first" do
      @open_pull.update!   created_at: 1.month.ago
      @closed_pull.update! created_at: 1.week.ago
      @other_pull.update!  created_at: 1.day.ago
      @merged_pull.update! created_at: 1.hour.ago

      expected = [@merged_pull, @other_pull, @closed_pull, @open_pull]
      assert_equal expected, PullRequest.by_creation("desc")
    end

    test "can fetch oldest first" do
      @open_pull.update!   created_at: 1.month.ago
      @closed_pull.update! created_at: 1.week.ago
      @other_pull.update!  created_at: 1.day.ago
      @merged_pull.update! created_at: 1.hour.ago

      expected = [@open_pull, @closed_pull, @other_pull, @merged_pull]
      assert_equal expected, PullRequest.by_creation("asc")
    end

    test "default ordering is oldest first" do
      @open_pull.update!   created_at: 1.month.ago
      @closed_pull.update! created_at: 1.week.ago
      @other_pull.update!  created_at: 1.day.ago
      @merged_pull.update! created_at: 1.hour.ago

      expected = [@open_pull, @closed_pull, @other_pull, @merged_pull]
      assert_equal expected, PullRequest.by_creation
    end
  end

  context "fetching pull requests ordered by update time" do
    test "can fetch most recent first" do
      Timecop.freeze(1.month.ago) { @open_pull.update_attribute(:created_at, Time.now)   }
      Timecop.freeze(1.week.ago)  { @closed_pull.update_attribute(:created_at, Time.now) }
      Timecop.freeze(1.day.ago)   { @other_pull.update_attribute(:created_at, Time.now)  }
      Timecop.freeze(1.hour.ago)  { @merged_pull.update_attribute(:created_at, Time.now) }

      expected = [@merged_pull, @other_pull, @closed_pull, @open_pull]
      assert_equal expected, PullRequest.by_updates("desc")
    end

    test "can fetch oldest first" do
      Timecop.freeze(1.month.ago) { @open_pull.update_attribute(:created_at, Time.now)   }
      Timecop.freeze(1.week.ago)  { @closed_pull.update_attribute(:created_at, Time.now) }
      Timecop.freeze(1.day.ago)   { @other_pull.update_attribute(:created_at, Time.now)  }
      Timecop.freeze(1.hour.ago)  { @merged_pull.update_attribute(:created_at, Time.now) }

      expected = [@open_pull, @closed_pull, @other_pull, @merged_pull]
      assert_equal expected, PullRequest.by_updates("asc")
    end

    test "default ordering is oldest first" do
      Timecop.freeze(1.month.ago) { @open_pull.update_attribute(:created_at, Time.now)   }
      Timecop.freeze(1.week.ago)  { @closed_pull.update_attribute(:created_at, Time.now) }
      Timecop.freeze(1.day.ago)   { @other_pull.update_attribute(:created_at, Time.now)  }
      Timecop.freeze(1.hour.ago)  { @merged_pull.update_attribute(:created_at, Time.now) }

      expected = [@open_pull, @closed_pull, @other_pull, @merged_pull]
      assert_equal expected, PullRequest.by_updates
    end
  end

  context "fetching pull requests ordered by longevity" do
    test "can fetch longest first" do
      Timecop.freeze(1.week.ago) { @open_pull.update_attribute(:created_at,   1.year.ago)   }
      Timecop.freeze(3.days.ago) { @closed_pull.update_attribute(:created_at, 6.months.ago) }
      Timecop.freeze(1.day.ago)  { @other_pull.update_attribute(:created_at,  3.months.ago) }
      Timecop.freeze(2.days.ago) { @merged_pull.update_attribute(:created_at, 1.month.ago)  }

      expected = [@open_pull, @closed_pull, @other_pull, @merged_pull]
      assert_equal expected, PullRequest.by_longevity("desc")
    end

    test "can fetch shortest first" do
      Timecop.freeze(1.week.ago) { @open_pull.update_attribute(:created_at,   1.year.ago)   }
      Timecop.freeze(3.days.ago) { @closed_pull.update_attribute(:created_at, 6.months.ago) }
      Timecop.freeze(1.day.ago)  { @other_pull.update_attribute(:created_at,  3.months.ago) }
      Timecop.freeze(2.days.ago) { @merged_pull.update_attribute(:created_at, 1.month.ago)  }

      expected = [@merged_pull, @other_pull, @closed_pull, @open_pull]
      assert_equal expected, PullRequest.by_longevity("asc")
    end

    test "default ordering is shortest first" do
      Timecop.freeze(1.week.ago) { @open_pull.update_attribute(:created_at,   1.year.ago)   }
      Timecop.freeze(3.days.ago) { @closed_pull.update_attribute(:created_at, 6.months.ago) }
      Timecop.freeze(1.day.ago)  { @other_pull.update_attribute(:created_at,  3.months.ago) }
      Timecop.freeze(2.days.ago) { @merged_pull.update_attribute(:created_at, 1.month.ago)  }

      expected = [@merged_pull, @other_pull, @closed_pull, @open_pull]
      assert_equal expected, PullRequest.by_longevity
    end
  end

  context "fetching pull requests ordered by popularity" do
    test "can fetch least popular first" do
      {
        @open_pull   => 3,
        @other_pull  => 2,
        @closed_pull => 1,
      }.each do |pull, count|
        count.times { create :issue_comment, issue: pull.issue }
      end

      expected = [@merged_pull, @closed_pull, @other_pull, @open_pull]
      assert_equal expected, PullRequest.by_popularity("asc")
    end

    test "can fetch most popular first" do
      {
        @open_pull   => 3,
        @other_pull  => 2,
        @closed_pull => 1,
      }.each do |pull, count|
        count.times { create :issue_comment, issue: pull.issue }
      end

      expected = [@open_pull, @other_pull, @closed_pull, @merged_pull]
      assert_equal expected, PullRequest.by_popularity("desc")
    end

    test "default ordering is least popular first" do
      {
        @open_pull   => 3,
        @other_pull  => 2,
        @closed_pull => 1,
      }.each do |pull, count|
        count.times { create :issue_comment, issue: pull.issue }
      end

      expected = [@merged_pull, @closed_pull, @other_pull, @open_pull]
      assert_equal expected, PullRequest.by_popularity
    end
  end

  context "fetching pull requests, excluding by open/closed state" do
    test "has issues.repository_id as a condition to allow optimized index usage" do
      assert_queries_matching(/`issues`.`repository_id` = `pull_requests`.`repository_id`/, 1) do
        PullRequest.excluding_states("open").load
      end
    end

    test "can exclude open pull requests" do
      expected = [@closed_pull, @merged_pull]
      assert_same_elements expected, PullRequest.excluding_states("open").to_a
    end

    test "can exclude closed pull requests" do
      expected = [@open_pull, @other_pull]
      assert_same_elements expected, PullRequest.excluding_states("closed").to_a
    end

    # TODO: this is damned near useless, should go away with user2AX pulls browser
    test "can exclude both open and closed pull requests" do
      assert_equal [], PullRequest.excluding_states("open,closed")
    end

    test "default is to exclude closed pull requests when exclusions are not specified" do
      expected = [@open_pull, @other_pull]
      assert_same_elements expected, PullRequest.excluding_states.to_a
    end
  end

  # NOTE: excludes closed pull requests by default
  context "filtering and ordering pull requests" do
    test "can order by creation" do
      @open_pull.update!   created_at: 1.month.ago
      @closed_pull.update! created_at: 1.week.ago
      @other_pull.update!  created_at: 1.day.ago
      @merged_pull.update! created_at: 1.hour.ago

      expected = [@open_pull, @other_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "created")
    end

    test "can order by updates" do
      Timecop.freeze(1.month.ago) { @open_pull.update_attribute(:created_at, Time.now)   }
      Timecop.freeze(1.week.ago)  { @closed_pull.update_attribute(:created_at, Time.now) }
      Timecop.freeze(1.day.ago)   { @other_pull.update_attribute(:created_at, Time.now)  }
      Timecop.freeze(1.hour.ago)  { @merged_pull.update_attribute(:created_at, Time.now) }

      expected = [@open_pull, @other_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "updated")
    end

    test "can order by popularity" do
      {
        @open_pull   => 3,
        @other_pull  => 2,
        @closed_pull => 1,
      }.each do |pull, count|
        count.times { create :issue_comment, issue: pull.issue }
      end

      expected = [@other_pull, @open_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "popularity")
    end

    test "can order by longevity" do
      Timecop.freeze(1.week.ago) { @open_pull.update_attribute(:created_at,   1.year.ago)   }
      Timecop.freeze(3.days.ago) { @closed_pull.update_attribute(:created_at, 6.months.ago) }
      Timecop.freeze(1.day.ago)  { @other_pull.update_attribute(:created_at,  3.months.ago) }
      Timecop.freeze(2.days.ago) { @merged_pull.update_attribute(:created_at, 1.month.ago)  }

      expected = [@other_pull, @open_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "longevity")
    end

    test "defaults to ordering by creation with newest first" do
      @open_pull.update!   created_at: 1.month.ago
      @closed_pull.update! created_at: 1.week.ago
      @other_pull.update!  created_at: 1.day.ago
      @merged_pull.update! created_at: 1.hour.ago

      expected = [@other_pull, @open_pull]
      assert_equal expected, PullRequest.filtered_and_ordered
    end

    test "does not add an unnecessary LEFT OUTER JOIN to the default query" do
      @open_pull.update!   created_at: 1.month.ago
      @closed_pull.update! created_at: 1.week.ago
      @other_pull.update!  created_at: 1.day.ago
      @merged_pull.update! created_at: 1.hour.ago

      _, queries = log_queries { PullRequest.filtered_and_ordered.all }

      refute queries.any? { |q| /LEFT OUTER JOIN `issues`/ =~ q.sql }, queries.map(&:sql).inspect
    end

    test "can specify direction by which to order results when a sort is specified" do
      @open_pull.update!   created_at: 1.month.ago
      @closed_pull.update! created_at: 1.week.ago
      @other_pull.update!  created_at: 1.day.ago
      @merged_pull.update! created_at: 1.hour.ago

      expected = [@open_pull, @other_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "created", direction: "asc")
    end

    test "with a specified sort order returns results in ascending order by default" do
      Timecop.freeze(1.month.ago) { @open_pull.update_attribute(:created_at, Time.now)   }
      Timecop.freeze(1.week.ago)  { @closed_pull.update_attribute(:created_at, Time.now) }
      Timecop.freeze(1.day.ago)   { @other_pull.update_attribute(:created_at, Time.now)  }
      Timecop.freeze(1.hour.ago)  { @merged_pull.update_attribute(:created_at, Time.now) }

      expected = [@open_pull, @other_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "updated")
    end

    test "can specify which pull requests to exclude" do
      Timecop.freeze(1.month.ago) { @open_pull.update_attribute(:created_at, Time.now)   }
      Timecop.freeze(1.week.ago)  { @closed_pull.update_attribute(:created_at, Time.now) }
      Timecop.freeze(1.day.ago)   { @other_pull.update_attribute(:created_at, Time.now)  }
      Timecop.freeze(1.hour.ago)  { @merged_pull.update_attribute(:created_at, Time.now) }

      expected = [@closed_pull, @merged_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "updated", exclude: "open")
    end

    test "excludes closed pull requests by default" do
      Timecop.freeze(1.month.ago) { @open_pull.update_attribute(:created_at, Time.now)   }
      Timecop.freeze(1.week.ago)  { @closed_pull.update_attribute(:created_at, Time.now) }
      Timecop.freeze(1.day.ago)   { @other_pull.update_attribute(:created_at, Time.now)  }
      Timecop.freeze(1.hour.ago)  { @merged_pull.update_attribute(:created_at, Time.now) }

      expected = [@open_pull, @other_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "updated")
    end

    test "can specify that only pull requests in the open state should be included" do
      Timecop.freeze(1.month.ago) { @open_pull.update_attribute(:created_at, Time.now)   }
      Timecop.freeze(1.week.ago)  { @closed_pull.update_attribute(:created_at, Time.now) }
      Timecop.freeze(1.day.ago)   { @other_pull.update_attribute(:created_at, Time.now)  }
      Timecop.freeze(1.hour.ago)  { @merged_pull.update_attribute(:created_at, Time.now) }

      expected = [@open_pull, @other_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "updated", state: "open")
    end

    test "can specify that only pull requests in the closed state should be included" do
      Timecop.freeze(1.month.ago) { @open_pull.update_attribute(:created_at, Time.now)   }
      Timecop.freeze(1.week.ago)  { @closed_pull.update_attribute(:created_at, Time.now) }
      Timecop.freeze(1.day.ago)   { @other_pull.update_attribute(:created_at, Time.now)  }
      Timecop.freeze(1.hour.ago)  { @merged_pull.update_attribute(:created_at, Time.now) }

      expected = [@closed_pull, @merged_pull]
      assert_equal expected, PullRequest.filtered_and_ordered(sort: "updated", state: "closed")
    end
  end

  context "PullRequest.with_number_and_repo" do
    test "finding nil" do
      assert_nil PullRequest.with_number_and_repo(-1, @source)
    end

    test "finds pull when scoped through the repo" do
      pull = PullRequest.with_number_and_repo(@open_pull.number, @source)
      assert_equal @open_pull, pull
    end

    test "does not find pull when scoped through non associated repo" do
      other_repo = create(:repository)
      assert_nil PullRequest.with_number_and_repo(@open_pull.number, other_repo)
    end

    test "returns a writable pull request" do
      pull = PullRequest.with_number_and_repo(@open_pull.number, @source)
      assert_equal @open_pull, pull
      refute pull.readonly?, "Pull should not be readonly"
      pull.head_ref = "new-head-ref"
      pull.save!
    end
  end
end
