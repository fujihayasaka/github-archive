# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitContributionSummaryTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers
  include PlatformTestHelpers::InterfaceHelpers

  fixtures do
    @user = create(:user, email: "chris@ozmm.org")
    @repository = create(:repository, owner: @user, from_example: :defunkt_facebox)

    @contributor = create(:user, email: "luke@lukemelia.com")
    @repository.add_member(@contributor)
  end

  test "is deleted with repository" do
    summary = create(:commit_contribution_summary, repository: @repository, user: @user)
    other_summary = create(:commit_contribution_summary, repository: create(:repository))

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repository
      config.expect_destroyed = [summary]
      config.expect_not_destroyed = [other_summary]
    end
  end

  context "accessors" do
    test "writes and reads counts" do
      counts = 365.times.map { rand(100) }
      written_summary = create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: counts)

      assert read_summary = CommitContributionSummary.find_by(id: written_summary.id)
      assert_equal counts, read_summary&.counts
    end

    test "writes and reads nibble-sized counts" do
      counts = Array.new(364, 14) << 14
      written_summary = create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: counts)

      read_summary = CommitContributionSummary.find_by(id: written_summary.id)
      refute_nil read_summary
      assert_equal counts, read_summary&.counts
    end

    test "writes and reads byte-sized counts" do
      counts = Array.new(364, 14) << 255
      written_summary = create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: counts)

      read_summary = CommitContributionSummary.find_by(id: written_summary.id)
      refute_nil read_summary
      assert_equal counts, read_summary&.counts
    end

    test "writes and reads smallint-sized counts" do
      counts = Array.new(364, 14) << 65535
      written_summary = create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: counts)

      read_summary = CommitContributionSummary.find_by(id: written_summary.id)
      refute_nil read_summary
      assert_equal counts, read_summary&.counts
    end

    test "writes and reads int-sized counts" do
      counts = Array.new(364, 14) << 4294967295
      written_summary = create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: counts)

      read_summary = CommitContributionSummary.find_by(id: written_summary.id)
      refute_nil read_summary
      assert_equal counts, read_summary&.counts
    end

    test "normalizes counts when saving" do
      counts = []
      counts[26] = 42

      written_summary = create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: counts)

      test_counts = Array.new(365, 0).fill(42, 26, 1)
      assert_equal test_counts, written_summary.counts

      read_summary = CommitContributionSummary.find_by(id: written_summary.id)
      refute_nil read_summary
      assert_equal test_counts, read_summary&.counts
    end

    test "updates the total count when saving" do
      counts = Array.new(365, 1)
      summary = CommitContributionSummary.build(repository: @repository, user: @user, year: non_leap_year, counts: counts)

      assert_nil summary.total_count
      summary.save!
      assert_equal 365, summary.total_count
    end
  end

  context "validations" do
    test "validates uniqueness by repository/user/year" do
      other_user = create(:user)
      other_repository = create(:repository, owner: other_user)

      # Existing summary
      create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: sample_counts)

      new_summary = CommitContributionSummary.new(repository: @repository, user: @user, year: non_leap_year, counts: sample_counts)
      refute_predicate new_summary, :valid?
      assert_includes new_summary.errors[:year], "has already been taken"

      # Valid with a different year
      refute_predicate new_summary, :valid?
      new_summary.year = non_leap_year - 2
      assert_predicate new_summary, :valid?
      new_summary.year = non_leap_year

      # Valid with a different user
      refute_predicate new_summary, :valid?
      new_summary.user = other_user
      assert_predicate new_summary, :valid?
      new_summary.user = @user

      # Valid with a different repo
      refute_predicate new_summary, :valid?
      new_summary.repository = other_repository
      assert_predicate new_summary, :valid?
      new_summary.repository = @repository
    end

    test "validates the presence of a year" do
      summary = CommitContributionSummary.new(repository: @repository, user: @user, counts: sample_counts)
      refute_predicate summary, :valid?
      assert_includes summary.errors[:year], "can't be blank"
    end

    test "validates the numericality of year" do
      summary = CommitContributionSummary.new(repository: @repository, user: @user, counts: sample_counts, year: "two thousand seven")
      refute_predicate summary, :valid?
      assert_includes summary.errors[:year], "is not a number"
    end

    test "validates the year is in range" do
      summary = CommitContributionSummary.new(repository: @repository, user: @user, counts: sample_counts, year: 1968)
      refute_predicate summary, :valid?
      assert_includes summary.errors[:year], "must be greater than or equal to 1969"
    end

    test "validates there is at least one contribution" do
      summary = CommitContributionSummary.new(repository: @repository, user: @user, year: non_leap_year)

      summary.counts = Array.new(365, 0)
      refute_predicate summary, :valid?
      assert_includes summary.errors[:counts], "must have at least one contribution during the year"
      summary.counts[0] = 1
      assert_predicate summary, :valid?
    end
  end

  context "CommitContributionSummary::Collection" do
    test "overwrites existing contribution history" do
      preexisting_counts = {
        Date.new(non_leap_year, 1, 1) => 42,
        Date.new(non_leap_year, 3, 1) => 42,
        Date.new(non_leap_year, 6, 1) => 42,
        Date.new(non_leap_year, 9, 1) => 42,
      }.each_with_object([]) { |(date, count), counts| counts[date.yday - 1] = count }

      existing_summary = create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: preexisting_counts)

      # Simulate a push with counts that should be overlap with the existing summary above as well as counts that
      # should be added to a new summary.
      new_counts_by_date = {
        Date.new(non_leap_year - 1, 12, 31) => 42,
        Date.new(non_leap_year, 6, 1) => 42,
        Date.new(non_leap_year, 6, 8) => 42,
        Date.new(non_leap_year, 6, 15) => 42,
      }

      assert_changes -> { CommitContributionSummary.count }, from: 1, to: 2 do
        # Ensure new counts in both past and future are included
        Timecop.travel(Date.new(non_leap_year, 6, 2)) do
          collection = CommitContributionSummary::Collection.new(repository: @repository)
          new_counts_by_date.each { |date, count| collection.add(user_id: @user.id, date: date, count: count) }
          collection.replace!
        end
      end

      expected_counts = {
        Date.new(non_leap_year, 6, 1) => 42,
        Date.new(non_leap_year, 6, 8) => 42,
        Date.new(non_leap_year, 6, 15) => 42,
      }.each_with_object(Array.new(365, 0)) { |(date, count), counts| counts[date.yday - 1] = count }

      replaced_summary = CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year)
      refute_nil replaced_summary
      refute_equal existing_summary.id, replaced_summary&.id
      assert_equal expected_counts, replaced_summary&.counts
      assert_equal expected_counts.sum, replaced_summary&.total_count

      expected_counts = Array.new(364, 0) << 42
      new_summary = CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year - 1)
      refute_nil new_summary
      assert_equal expected_counts, new_summary&.counts
      assert_equal 42, new_summary&.total_count
    end

    test "merges with existing contribution history" do
      preexisting_counts = {
        Date.new(non_leap_year, 1, 1) => 42,
        Date.new(non_leap_year, 3, 1) => 42,
        Date.new(non_leap_year, 6, 1) => 42,
        Date.new(non_leap_year, 9, 1) => 42,
      }.each_with_object([]) { |(date, count), counts| counts[date.yday - 1] = count }

      create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: preexisting_counts)

      # Simulate a push with counts that should be overlap with the existing summary above as well as counts that
      # should be added to a new summary.
      new_counts_by_date = {
        Date.new(non_leap_year - 1, 12, 31) => 42,
        Date.new(non_leap_year, 6, 1) => 42,
        Date.new(non_leap_year, 6, 8) => 42,
        Date.new(non_leap_year, 6, 15) => 42,
      }

      assert_changes -> { CommitContributionSummary.count }, from: 1, to: 2 do
        # Ensure new counts in both past and future are included
        Timecop.travel(Date.new(non_leap_year, 6, 2)) do
          collection = CommitContributionSummary::Collection.new(repository: @repository)
          new_counts_by_date.each { |date, count| collection.add(user_id: @user.id, date: date, count: count) }
          collection.update!
        end
      end

      expected_counts = {
        Date.new(non_leap_year, 1, 1) => 42,
        Date.new(non_leap_year, 3, 1) => 42,
        Date.new(non_leap_year, 6, 1) => 84,
        Date.new(non_leap_year, 6, 8) => 42,
        Date.new(non_leap_year, 6, 15) => 42,
        Date.new(non_leap_year, 9, 1) => 42,
      }.each_with_object(Array.new(365, 0)) { |(date, count), counts| counts[date.yday - 1] = count }

      existing_summary = CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year)
      refute_nil existing_summary
      assert_equal expected_counts, existing_summary&.counts
      assert_equal expected_counts.sum, existing_summary&.total_count

      expected_counts = Array.new(364, 0) << 42
      new_summary = CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year - 1)
      refute_nil new_summary
      assert_equal expected_counts, new_summary&.counts
      assert_equal 42, new_summary&.total_count
    end

    test "handles a summary sneaking in after an update started" do
      # Simulate an update with a count for 1/2
      collection = CommitContributionSummary::Collection.new(repository: @repository)
      collection.add(user_id: @user.id, date: Date.new(non_leap_year, 1, 2), count: 42)

      # Sneak in a summary with a count on 1/1
      create_conflicting_summary = proc do
        preexisting_counts = Array.new(365, 0).fill(21, 0, 1)
        create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: preexisting_counts)
      end
      test_throttler = TestThrottler.new(before_throttle: create_conflicting_summary)
      CommitContributionSummary.stubs(:throttler).returns(test_throttler)

      existing_summary = CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year)
      assert_nil existing_summary

      # This should try to create a summary, catch an ActiveRecord::RecordInvalid, and update the summary we snuck in
      collection.update!

      new_summary = CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year)
      refute_nil new_summary
      expected_counts = [21, 42] + Array.new(363, 0)
      assert_equal expected_counts, new_summary&.counts
      assert_equal 63, new_summary&.total_count
    end
  end

  context "backfill_repository" do
    unless GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
      test "backfills from CommitContribution records for a repository when the flag is disabled" do
        disable_feature_flag(:skip_commit_contributions, @repository)

        user_not_in_contribution_history = create(:user)
        create(:commit_contribution, user: user_not_in_contribution_history, repository: @repository)
        create(:commit_contribution_summary, user: @user, repository: @repository)

        CommitContribution.expects(:backfill!).never
        CommitContributionSummary.backfill_repository(@repository)

        # @user and @contributor have contributions in git, but not in CommitContribution records;
        # backfill should create summaries for all commit_contributions records, which should only
        # include the user_not_in_contribution_history - and should also remove existing summaries
        # for users that do not have commit_contribution records, eg. @user.
        refute_empty CommitContributionSummary.for_repository(@repository).for_user(user_not_in_contribution_history)
        assert_empty CommitContributionSummary.for_repository(@repository).for_user(@user)
        assert_empty CommitContributionSummary.for_repository(@repository).for_user(@contributor)
      end

      test "backfills from CommitContribution records for a repository and a user when the flag is disabled" do
        disable_feature_flag(:skip_commit_contributions, @repository)

        user_not_in_contribution_history = create(:user)
        create(:commit_contribution, user: user_not_in_contribution_history, repository: @repository)
        create(:commit_contribution_summary, user: @user, repository: @repository)

        CommitContribution.expects(:backfill!).never
        CommitContributionSummary.backfill_repository(@repository, user_not_in_contribution_history)

        # @user and @contributor have contributions in git, but not in CommitContribution records;
        # backfill should create summaries for all commit_contributions records, which should only
        # include the user_not_in_contribution_history - and should not affect summaries for other
        # users even if they don't have commit_contributions records, eg. @user.
        refute_empty CommitContributionSummary.for_repository(@repository).for_user(user_not_in_contribution_history)
        refute_empty CommitContributionSummary.for_repository(@repository).for_user(@user)
        assert_empty CommitContributionSummary.for_repository(@repository).for_user(@contributor)
      end

      test "uses CommitContribution backfill for a repository when the flag is enabled" do
        enable_feature_flag(:skip_commit_contributions, @repository)

        user_not_in_contribution_history = create(:user)
        create(:commit_contribution, :with_summaries, user: user_not_in_contribution_history, repository: @repository)

        refute_empty CommitContributionSummary.for_repository(@repository).for_user(user_not_in_contribution_history)
        assert_empty CommitContributionSummary.for_repository(@repository).for_user(@user)
        assert_empty CommitContributionSummary.for_repository(@repository).for_user(@contributor)

        CommitContributionSummary.expects(:no_ghost_users).never
        CommitContributionSummary.backfill_repository(@repository)

        # Backfill should create summaries for only users who have contributions in git, and should
        # remove existing summaries for users who do not have contributions in git.
        assert_empty CommitContributionSummary.for_repository(@repository).for_user(user_not_in_contribution_history)
        refute_empty CommitContributionSummary.for_repository(@repository).for_user(@user)
        refute_empty CommitContributionSummary.for_repository(@repository).for_user(@contributor)
      end

      test "uses CommitContribution backfill for a repository and a user when the flag is enabled" do
        enable_feature_flag(:skip_commit_contributions, @repository)

        user_not_in_contribution_history = create(:user)
        create(:commit_contribution, :with_summaries, user: user_not_in_contribution_history, repository: @repository)

        refute_empty CommitContributionSummary.for_repository(@repository).for_user(user_not_in_contribution_history)
        assert_empty CommitContributionSummary.for_repository(@repository).for_user(@user)
        assert_empty CommitContributionSummary.for_repository(@repository).for_user(@contributor)

        CommitContributionSummary.expects(:no_ghost_users).never
        CommitContributionSummary.backfill_repository(@repository, @user)

        # Backfill should create summaries for only only specified users who have contributions in git,
        # and should not affect existing summaries for other users even if they have no contributions in git.
        refute_empty CommitContributionSummary.for_repository(@repository).for_user(user_not_in_contribution_history)
        refute_empty CommitContributionSummary.for_repository(@repository).for_user(@user)
        assert_empty CommitContributionSummary.for_repository(@repository).for_user(@contributor)
      end
    end

    test "ignores ghost contributions" do
      # Test legacy backfill behavior when always using CommitContribution data as a source of truth.
      disable_feature_flag(:skip_commit_contributions, @repository)

      create(:commit_contribution, user: User.ghost, repository: @repository, committed_date: Date.new(non_leap_year, 1, 1), commit_count: 42)

      assert_no_changes -> { CommitContributionSummary.count } do
        CommitContributionSummary.backfill_repository(@repository)
      end
    end

    test "ignores contributions with zero commit counts" do
      # Test legacy backfill behavior when always using CommitContribution data as a source of truth.
      disable_feature_flag(:skip_commit_contributions, @repository)

      create(:commit_contribution, user: @user, repository: @repository, committed_date: Date.new(non_leap_year, 1, 1), commit_count: 0)

      assert_no_changes -> { CommitContributionSummary.count } do
        CommitContributionSummary.backfill_repository(@repository)
      end
    end

    test "ignores contributions with no commit date" do
      # Test legacy backfill behavior when always using CommitContribution data as a source of truth.
      disable_feature_flag(:skip_commit_contributions, @repository)

      create(:commit_contribution, user: @user, repository: @repository, committed_date: nil, commit_count: 42)

      assert_no_changes -> { CommitContributionSummary.count } do
        CommitContributionSummary.backfill_repository(@repository)
      end
    end

    test "removes summaries for users who have no contributions" do
      # Test legacy backfill behavior when always using CommitContribution data as a source of truth.
      disable_feature_flag(:skip_commit_contributions, @repository)

      other_contributor1, other_contributor2 = create_list(:user, 2)
      @repository.add_member(other_contributor1)
      @repository.add_member(other_contributor2)
      other_repo = create(:repository, owner: other_contributor1)

      create(:commit_contribution, user: @user, repository: @repository, committed_date: Date.new(non_leap_year, 1, 1), commit_count: 42)

      create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: sample_counts)
      create(:commit_contribution_summary, repository: @repository, user: other_contributor1, year: non_leap_year, counts: sample_counts)
      create(:commit_contribution_summary, repository: @repository, user: other_contributor2, year: non_leap_year, counts: sample_counts)
      create(:commit_contribution_summary, repository: other_repo, user: other_contributor1, year: non_leap_year, counts: sample_counts)

      refute_nil CommitContributionSummary.find_by(repository: @repository, user: @user)
      refute_nil CommitContributionSummary.find_by(repository: @repository, user: other_contributor1)
      refute_nil CommitContributionSummary.find_by(repository: @repository, user: other_contributor2)
      refute_nil CommitContributionSummary.find_by(repository: other_repo, user: other_contributor1)
      CommitContributionSummary.backfill_repository(@repository)
      refute_nil CommitContributionSummary.find_by(repository: @repository, user: @user)
      assert_nil CommitContributionSummary.find_by(repository: @repository, user: other_contributor1)
      assert_nil CommitContributionSummary.find_by(repository: @repository, user: other_contributor2)
      refute_nil CommitContributionSummary.find_by(repository: other_repo, user: other_contributor1)
    end

    test "updates summary records for all contributors to the repository" do
      # Test legacy backfill behavior when always using CommitContribution data as a source of truth.
      disable_feature_flag(:skip_commit_contributions, @repository)

      other_contributor = create(:user)
      @repository.add_member(other_contributor)

      create(:commit_contribution, user: @user, repository: @repository, committed_date: Date.new(non_leap_year, 1, 1), commit_count: 42)
      create(:commit_contribution, user: @user, repository: @repository, committed_date: Date.new(non_leap_year, 12, 31), commit_count: 42)
      create(:commit_contribution, user: other_contributor, repository: @repository, committed_date: Date.new(non_leap_year, 1, 1), commit_count: 42)
      create(:commit_contribution, user: other_contributor, repository: @repository, committed_date: Date.new(non_leap_year, 12, 31), commit_count: 42)

      orig_user_summary = create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: Array.new(365, 1))

      expected_counts = Array.new(363, 0).unshift(42) << 42

      assert_changes -> { CommitContributionSummary.count }, from: 1, to: 2 do
        # This also ensures that commit contributions with future dates are included in the summary
        Timecop.travel(Date.new(non_leap_year, 7, 1)) do
          CommitContributionSummary.backfill_repository(@repository)
        end
      end

      assert_raises(ActiveRecord::RecordNotFound) { orig_user_summary.reload }
      user_summary = CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year)
      refute_nil user_summary
      assert_equal 84, user_summary&.total_count
      assert_equal expected_counts, user_summary&.counts

      other_summary = CommitContributionSummary.find_by(repository: @repository, user: other_contributor, year: non_leap_year)
      refute_nil other_summary
      assert_equal 84, other_summary&.total_count
      assert_equal expected_counts, other_summary&.counts
    end

    test "backfills for users that don't have contributions for each year" do
      # Test legacy backfill behavior when always using CommitContribution data as a source of truth.
      disable_feature_flag(:skip_commit_contributions, @repository)

      other_contributor = create(:user)
      @repository.add_member(other_contributor)

      create(:commit_contribution, user: @user, repository: @repository, committed_date: Date.new(2022, 1, 10), commit_count: 42)
      create(:commit_contribution, user: @user, repository: @repository, committed_date: Date.new(2023, 1, 10), commit_count: 42)
      create(:commit_contribution, user: @user, repository: @repository, committed_date: Date.new(2024, 1, 10), commit_count: 42)
      create(:commit_contribution, user: other_contributor, repository: @repository, committed_date: Date.new(2023, 1, 10), commit_count: 42)

      CommitContributionSummary.backfill_repository(@repository)

      refute_nil CommitContributionSummary.find_by(repository: @repository, user: @user, year: 2022)
      refute_nil CommitContributionSummary.find_by(repository: @repository, user: @user, year: 2023)
      refute_nil CommitContributionSummary.find_by(repository: @repository, user: @user, year: 2024)

      assert_nil CommitContributionSummary.find_by(repository: @repository, user: other_contributor, year: 2022)
      refute_nil CommitContributionSummary.find_by(repository: @repository, user: other_contributor, year: 2023)
      assert_nil CommitContributionSummary.find_by(repository: @repository, user: other_contributor, year: 2024)
    end

    test "clears old summary records before backfilling" do
      # Test legacy backfill behavior when always using CommitContribution data as a source of truth.
      disable_feature_flag(:skip_commit_contributions, @repository)

      create(:commit_contribution, user: @user, repository: @repository, committed_date: Date.new(leap_year, 1, 1), commit_count: 42)

      create(:commit_contribution_summary, repository: @repository, user: @user, year: non_leap_year, counts: sample_counts)

      refute_nil CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year)
      assert_nil CommitContributionSummary.find_by(repository: @repository, user: @user, year: leap_year)

      CommitContributionSummary.backfill_repository(@repository)

      assert_nil CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year)
      refute_nil CommitContributionSummary.find_by(repository: @repository, user: @user, year: leap_year)
    end

    test "backfills for a specified user" do
      # Test legacy backfill behavior when always using CommitContribution data as a source of truth.
      disable_feature_flag(:skip_commit_contributions, @repository)

      other_contributor = create(:user)
      @repository.add_member(other_contributor)

      create(:commit_contribution, user: @user, repository: @repository, committed_date: Date.new(non_leap_year, 1, 10), commit_count: 42)
      create(:commit_contribution, user: other_contributor, repository: @repository, committed_date: Date.new(non_leap_year, 1, 10), commit_count: 42)

      CommitContributionSummary.backfill_repository(@repository, @user)

      refute_nil CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year)
      assert_nil CommitContributionSummary.find_by(repository: @repository, user: other_contributor, year: non_leap_year)
    end

    test "does not clear other users summaries when backfilling for a specified user" do
      other_contributor = create(:user)
      @repository.add_member(other_contributor)

      create(:commit_contribution, :with_summaries, user: @user, repository: @repository, committed_date: Date.new(non_leap_year, 1, 10), commit_count: 42)
      create(:commit_contribution, :with_summaries, user: other_contributor, repository: @repository, committed_date: Date.new(non_leap_year, 1, 10), commit_count: 42)

      assert existing_user_summary = CommitContributionSummary.find_by(repository: @repository, user: @user, year: non_leap_year)
      assert existing_other_contributor_summary = CommitContributionSummary.find_by(repository: @repository, user: other_contributor, year: non_leap_year)

      CommitContributionSummary.backfill_repository(@repository, @user)

      # The backfilled user should have contributions whether they were backfilled from git or commit_contributions,
      # and they should be new summary records.
      refute_empty CommitContributionSummary.for_repository(@repository).for_user(@user)
      assert_empty CommitContributionSummary.for_repository(@repository).for_user(@user).where(id: T.must(existing_user_summary).id)

      # Summary records from other users should not be affected.
      assert same_other_contributor_summary = CommitContributionSummary.find_by(repository: @repository, user: other_contributor, year: non_leap_year)
      assert_equal T.must(existing_other_contributor_summary).id, T.must(same_other_contributor_summary).id
    end
  end

  # Used by GitHub::RepoGraph::ContributionInsights.fetch_contributors_data for eg. the repository insights contributors graph
  context "repository_contribution_history" do
    test "returns a hash in GitHub::RepoGraph::ContributionInsights#fetch_contributors_data format" do
      expected_dates = {
        @user.git_author_email => [],
        @contributor.git_author_email => [],
      }

      # Give the owner a long contribution history
      1.upto(3) do |year|
        contribution_counts = Array.new(365, 0)
        1.upto(12) do |month|
          contribution_date = Date.new(2020 + year, month, 1)
          contribution_counts[contribution_date.yday - 1] = 42
          expected_dates[@user.git_author_email] << contribution_date
        end
        create(:commit_contribution_summary, repository: @repository, user: @user, year: 2020 + year, counts: contribution_counts)
      end
      create(:commit_contribution, user: @user, repository: @repository) # for Repository#top_contributors

      # Give the contributor a short contribution history
      contribution_counts = Array.new(365, 0)
      3.upto(6) do |month|
        contribution_date = Date.new(2022, month, 1)
        contribution_counts[contribution_date.yday - 1] = 42
        expected_dates[@contributor.git_author_email] << contribution_date
      end
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2022, counts: contribution_counts)
      create(:commit_contribution, user: @contributor, repository: @repository) # for Repository#top_contributors

      users = [@user, @contributor]
      contribution_history = CommitContributionSummary.repository_contribution_history(repository: @repository, users: users)
      commit_history = T.must(contribution_history[:commits])
      addition_history = T.must(contribution_history[:additions])
      deletion_history = T.must(contribution_history[:deletions])

      assert_same_elements [@user.git_author_email, @contributor.git_author_email], commit_history.keys
      assert_same_elements [@user.git_author_email, @contributor.git_author_email], addition_history.keys
      assert_same_elements [@user.git_author_email, @contributor.git_author_email], deletion_history.keys

      expected_owner_commits = expected_dates[@user.git_author_email].inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 42) }
      expected_owner_changes = expected_dates[@user.git_author_email].inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 0) }
      assert_equal expected_owner_commits, commit_history[@user.git_author_email]
      assert_equal expected_owner_changes, addition_history[@user.git_author_email]
      assert_equal expected_owner_changes, deletion_history[@user.git_author_email]

      expected_contributor_commits = expected_dates[@contributor.git_author_email].inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 42) }
      expected_contributor_changes = expected_dates[@contributor.git_author_email].inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 0) }
      assert_equal expected_contributor_commits, commit_history[@contributor.git_author_email]
      assert_equal expected_contributor_changes, addition_history[@contributor.git_author_email]
      assert_equal expected_contributor_changes, deletion_history[@contributor.git_author_email]
    end

    test "limits results to specified users" do
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2024, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2024, counts: [42])

      contribution_history = CommitContributionSummary.repository_contribution_history(repository: @repository, users: [@user])

      assert_equal [@user.git_author_email], T.must(contribution_history[:commits]).keys
      assert_equal [@user.git_author_email], T.must(contribution_history[:additions]).keys
      assert_equal [@user.git_author_email], T.must(contribution_history[:deletions]).keys
    end
  end

  # Used by GitHub::RepoGraph::ContributionInsights.fetch_commit_activity_data for eg. the repository insights commits graph
  context "repository_commit_activity" do
    test "returns a hash in GitHub::RepoGraph::ContributionInsights#fetch_commit_activity_data format" do
      today = Date.parse("2023-06-15")
      one_year_ago = today - 1.year

      # Give the owner a long contribution history
      contribution_dates = []
      1.upto(3) do |year|
        contribution_counts = Array.new(365, 0)
        1.upto(12) do |month|
          date = Date.new(2020 + year, month, 1)
          if date > one_year_ago
            contribution_dates << date
            contribution_dates << date + 1.day
          end

          date_index = date.yday - 1
          contribution_counts[date_index] = 42
          contribution_counts[date_index + 1] = 42
        end
        create(:commit_contribution_summary, repository: @repository, user: @user, year: 2020 + year, counts: contribution_counts)
      end

      # Give the contributor a short contribution history
      overlap_dates = []
      contribution_counts = Array.new(365, 0)
      6.upto(9) do |month|
        date = Date.new(2022, month, 1)
        overlap_dates << date if date > one_year_ago

        date_index = date.yday - 1
        contribution_counts[date_index] = 42
      end
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2022, counts: contribution_counts)

      # Expect counts from @user on the first and second day of each month in range,
      # and overlapping counts from @contributor on the first of September-November.
      expected_counts = contribution_dates.inject({}) { |hash, date| hash.merge!(date.to_time.to_i => 42) }
      overlap_dates.each { |date| expected_counts[date.to_time.to_i] += 42 }

      commit_activity = travel_to(today) do
        CommitContributionSummary.repository_commit_activity(repository: @repository)
      end

      assert_equal expected_counts.to_a, commit_activity
    end
  end

  # Used by Contribution::CreatedCommit.subjects_for to eg. load contributions for the profile contribution graph
  context "commit_contributions_for" do
    test "returns CommitContribution records for the specified user and date range" do
      contribution_dates = [
        Date.new(2022, 1, 1),
        Date.new(2022, 6, 1),
        Date.new(2022, 12, 1),
        Date.new(2023, 1, 1),
        Date.new(2023, 6, 1),
        Date.new(2023, 12, 1),
      ]
      other_repo = create(:repository, owner: @user)

      contribution_dates.group_by(&:year).each do |year, dates|
        counts = dates.each_with_object(Array.new(365, 0)) { |date, counts| counts[date.yday - 1] = 42 }
        create(:commit_contribution_summary, repository: @repository, user: @user, year: year, counts: counts)
        create(:commit_contribution_summary, repository: other_repo, user: @user, year: year, counts: counts)
        create(:commit_contribution_summary, repository: @repository, user: @contributor, year: year, counts: counts)
      end

      date_range = Date.new(2022, 6, 1)..Date.new(2023, 6, 1)
      contributions = CommitContributionSummary.commit_contributions_for(user: @user, date_range: date_range, repositories: nil)

      assert_equal [@user], contributions.map(&:user).uniq
      assert_equal [@repository, other_repo].sort, contributions.map(&:repository).uniq.sort
      assert_equal [CommitContribution], contributions.map(&:class).uniq
      [@repository, other_repo].each do |repo|
        repo_contributions = contributions.select { |contribution| contribution.repository == repo }
        assert_equal contribution_dates[1..4], repo_contributions.map(&:committed_date).sort
        assert_equal [42, 42, 42, 42], repo_contributions.map(&:commit_count)
      end
    end

    test "scopes to repositories" do
      other_repo = create(:repository, owner: @user)
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: other_repo, user: @user, year: 2022, counts: [42])

      date_range = Date.new(2022, 1, 1)..Date.new(2022, 12, 31)
      contributions = CommitContributionSummary.commit_contributions_for(user: @user, date_range: date_range, repositories: [@repository])

      assert_equal [@repository], contributions.map(&:repository).uniq
    end

    test "works with ExternalIdentity::AdminableMember" do
      org = create(:business_plus_organization)
      identity = create :external_identity, org: org
      provider = identity.provider
      admin = TestEnv.test_with_all_emus? ? provider.business.find_emu_owners_except_first.last : org.admin
      user = identity.user

      repo = create(:public_repository, owner: org)
      travel_to(1.week.ago) do
        create(:commit_contribution, repository: repo, user: user, committed_date: Date.today, commit_count: 1)
        summary_counts = Array.new(365, 0).fill(1, Date.today.yday - 1, 1)
        create(:commit_contribution_summary, repository: repo, user: user, year: Date.today.year, counts: summary_counts)
      end

      results = execute_query(<<-"GRAPHQL", :$id => identity.global_relay_id, :viewer => admin)
        query($id: ID!) {
          node(id: $id) {
            ... on ExternalIdentity {
              guid
              user {
                contributionsCollection {
                  hasAnyContributions
                }
                login
              }
            }
          }
        }
      GRAPHQL

      assert_equal true, results.data["node"]["user"]["contributionsCollection"]["hasAnyContributions"]
    end
  end

  context "contributed_repo_ids" do
    test "returns the repository ids for which the user has contributions" do
      other_repo = create(:repository, owner: @user)

      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: other_repo, user: @user, year: 2022, counts: [42])

      contributed_repo_ids = CommitContributionSummary.contributed_repo_ids(user: @user, prior_to: nil, since: nil).sort
      assert_equal [@repository.id, other_repo.id].sort, contributed_repo_ids
    end

    test "finds repos the user committed to before a given date" do
      other_repo = create(:repository, owner: @user)

      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [42])
      create(:commit_contribution_summary, repository: other_repo, user: @user, year: 2023, counts: [42])

      prior_to = Date.new(2022, 6, 1)
      contributed_repo_ids = CommitContributionSummary.contributed_repo_ids(user: @user, prior_to: prior_to, since: nil)
      assert_equal [@repository.id], contributed_repo_ids
    end

    test "finds repos the user committed to after a given date" do
      other_repo = create(:repository, owner: @user)

      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [42])
      create(:commit_contribution_summary, repository: other_repo, user: @user, year: 2024, counts: [42])

      since = Date.new(2023, 6, 1)
      contributed_repo_ids = CommitContributionSummary.contributed_repo_ids(user: @user, prior_to: nil, since: since)
      assert_equal [other_repo.id], contributed_repo_ids
    end

    test "finds repos the user committed to between two dates" do
      too_early = create(:repository, owner: @user)
      too_late = create(:repository, owner: @user)
      just_right = create(:repository, owner: @user)

      create(:commit_contribution_summary, repository: too_early, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: too_late, user: @user, year: 2024, counts: [42])
      create(:commit_contribution_summary, repository: just_right, user: @user, year: 2023, counts: [42])

      since = Date.new(2022, 6, 1)
      prior_to = Date.new(2023, 6, 1)
      contributed_repo_ids = CommitContributionSummary.contributed_repo_ids(user: @user, since: since, prior_to: prior_to)
      assert_equal [just_right.id], contributed_repo_ids
    end
  end

  context "top_contributed_repository_ids" do
    test "ignores commits more than one year old" do
      other_repo = create(:repository, owner: @user)
      create(:commit_contribution_summary, repository: other_repo, user: @user, year: 2022, counts: [2])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [4])

      repo_ids = Timecop.freeze(Date.new(2023, 6, 1)) do
        CommitContributionSummary.top_contributed_repository_ids(user: @user, limit: 100, repository_ids: nil)
      end

      assert_equal [@repository.id], repo_ids
    end

    test "results are sorted with the most contributed repos first" do
      other_repo = create(:repository, owner: @user)
      create(:commit_contribution_summary, repository: other_repo, user: @user, year: 2023, counts: [2])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [4])

      repo_ids = Timecop.freeze(Date.new(2023, 6, 1)) do
        CommitContributionSummary.top_contributed_repository_ids(user: @user, limit: 100, repository_ids: nil)
      end

      assert_equal [@repository.id, other_repo.id], repo_ids
    end

    test "limits results to specific repositories" do
      other_repo = create(:repository, owner: @user)
      create(:commit_contribution_summary, repository: other_repo, user: @user, year: 2023, counts: [2])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [4])

      repo_ids = Timecop.freeze(Date.new(2023, 6, 1)) do
        CommitContributionSummary.top_contributed_repository_ids(user: @user, repository_ids: [@repository.id], limit: 100)
      end

      assert_equal [@repository.id], repo_ids
    end

    test "limits number of results" do
      other_repo = create(:repository, owner: @user)
      create(:commit_contribution_summary, repository: other_repo, user: @user, year: 2023, counts: [2])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [4])

      repo_ids = Timecop.freeze(Date.new(2023, 6, 1)) do
        CommitContributionSummary.top_contributed_repository_ids(user: @user, limit: 1, repository_ids: nil)
      end

      assert_equal [@repository.id], repo_ids
    end
  end

  context "contributed_user_ids" do
    test "returns the user ids for which the repository has contributions" do
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2022, counts: [42])

      contributed_user_ids = CommitContributionSummary.contributed_user_ids(repository: @repository)
      assert_same_elements [@user.id, @contributor.id], contributed_user_ids
    end

    test "scopes to a recent date range" do
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2022, counts: [42])

      since = Date.new(2022, 6, 1)
      contributed_user_ids = CommitContributionSummary.contributed_user_ids(repository: @repository, since: since)
      assert_same_elements [@user.id], contributed_user_ids
    end

    test "scopes to specific users" do
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: create(:user), year: 2022, counts: [42])

      contributed_user_ids = CommitContributionSummary.contributed_user_ids(repository: @repository, users: [@user, @contributor])
      assert_same_elements [@user.id, @contributor.id], contributed_user_ids
    end

    test "excludes contributions from the ghost user" do
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: User.ghost, year: 2022, counts: [42])

      contributed_user_ids = CommitContributionSummary.contributed_user_ids(repository: @repository, exclude_ghost: true)
      assert_same_elements [@user.id].sort, contributed_user_ids
    end
  end

  context "has_recent_contributions?" do
    test "true when a repository on the list has recent contributions" do
      other_repo1, other_repo2 = create_list(:repository, 2, owner: @user)

      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: other_repo1, user: @user, year: 2023, counts: [42])
      create(:commit_contribution_summary, repository: other_repo2, user: @user, year: 2022, counts: [42])

      assert CommitContributionSummary.has_recent_contributions?(repository_ids: [@repository.id, other_repo1.id, other_repo2.id], since: Date.new(2022, 7, 1))
    end

    test "false when no repositories on the list have recent contributions" do
      other_repo1, other_repo2 = create_list(:repository, 2, owner: @user)

      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: other_repo1, user: @user, year: 2023, counts: [42])
      create(:commit_contribution_summary, repository: other_repo2, user: @user, year: 2022, counts: [42])

      refute CommitContributionSummary.has_recent_contributions?(repository_ids: [@repository.id, other_repo2.id], since: Date.new(2022, 7, 1))
      refute CommitContributionSummary.has_recent_contributions?(repository_ids: [@repository.id, other_repo1.id, other_repo2.id], since: Date.new(2023, 7, 1))
    end
  end

  context "first_repository_contribution_date" do
    test "finds the first contribution date for the repository" do
      other_repo = create(:repository)
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [0, 42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2023, counts: [42])
      create(:commit_contribution_summary, repository: other_repo, user: @user, year: 2022, counts: [42])

      assert_equal Date.new(2023, 1, 1), CommitContributionSummary.first_repository_contribution_date(repository: @repository)
    end
  end

  context "days_with_commits_count_by_repo" do
    test "returns the number of days with commits in the date range for each repository" do
      other_repo1, other_repo2 = create_list(:repository, 2, owner: @user)
      repos = [@repository, other_repo1, other_repo2]

      [2021, 2022, 2023].each do |year|
        repos.each_with_index do |repo, i|
          counts = Array.new(365, 0)
          1.upto(12).each do |month|
            date = Date.new(year, month, 1)
            counts[date.yday - 1 + i] = 42
          end
          create(:commit_contribution_summary, repository: repo, user: @user, year: year, counts: counts)

          counts = Array.new(365, 0)
          1.upto(12).each do |month|
            date = Date.new(year, month, 4)
            counts[date.yday - 1 + i] = 42
          end
          create(:commit_contribution_summary, repository: repo, user: @contributor, year: year, counts: counts)
        end
      end

      counts = CommitContributionSummary.days_with_commits_count_by_repo(user: @user, since: Date.new(2022, 6, 15))
      assert_equal [@repository.id, other_repo1.id, other_repo2.id].sort, counts.keys.sort
      assert_equal [18, 18, 18], counts.values
    end
  end

  context "contributors_count_for_repository" do
    test "returns count with no date range" do
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: User.ghost, year: 2023, counts: [42])

      assert_equal 2, CommitContributionSummary.contributors_count_for_repository(@repository, since: nil)
    end

    test "returns count for contributions since a given date" do
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: User.ghost, year: 2023, counts: [42])

      start_date = Date.new(2022, 7, 1)
      assert_equal 1, CommitContributionSummary.contributors_count_for_repository(@repository, since: start_date)
    end
  end

  context "last_contribution_date" do
    test "returns the most recent commit date" do
      date1 = Date.new(2007, 10, 19)
      date2 = Date.new(2011, 9, 26)

      counts = Array.new(365, 0)
      counts[0] = 42
      counts[date1.yday - 1] = 42
      create(:commit_contribution_summary, repository: @repository, user: @user, year: date1.year, counts: counts)

      counts = Array.new(365, 0)
      counts[0] = 42
      counts[date2.yday - 1] = 42
      create(:commit_contribution_summary, repository: @repository, user: @user, year: date2.year, counts: counts)

      assert_equal date2, CommitContributionSummary.last_contribution_date(user: @user, repository: @repository)
    end

    test "returns nil when no contribution was found" do
      other_repo = create(:repository, owner: @user)

      date = Date.new(2023, 7, 1)
      counts = Array.new(365, 0).fill(42, date.yday - 1, 1)
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2023, counts: counts)

      assert_nil CommitContributionSummary.last_contribution_date(user: @user, repository: other_repo)
    end
  end

  context "first_contribution_date" do
    test "returns the oldest commit date" do
      date1 = Date.new(2007, 10, 19)
      date2 = Date.new(2011, 9, 26)

      counts = Array.new(365, 0)
      counts[365] = 42
      counts[date1.yday - 1] = 42
      create(:commit_contribution_summary, repository: @repository, user: @user, year: date1.year, counts: counts)

      counts = Array.new(365, 0)
      counts[0] = 42
      counts[date2.yday - 1] = 42
      create(:commit_contribution_summary, repository: @repository, user: @user, year: date2.year, counts: counts)

      assert_equal date1, CommitContributionSummary.first_contribution_date(user: @user)
    end

    test "returns nil when no contribution was found" do
      assert_empty CommitContributionSummary.for_user(@user)
      assert_nil CommitContributionSummary.first_contribution_date(user: @user)
    end
  end

  context "contributed_user_ids_by_recency" do
    test "returns user ids in order of most recent contributions" do
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2024, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2025, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2025, counts: [0, 42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2024, counts: [0, 42])

      assert_equal [@contributor.id, @user.id], CommitContributionSummary.contributed_user_ids_by_recency(repository: @repository, limit: 10)
    end

    test "excludes the Ghost user" do
      create(:commit_contribution_summary, repository: @repository, user: User.ghost, year: 1970, counts: [1])

      assert_empty CommitContributionSummary.contributed_user_ids_by_recency(repository: @repository, limit: 10)

      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2024, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2025, counts: [0, 42])

      assert_equal [@contributor.id, @user.id], CommitContributionSummary.contributed_user_ids_by_recency(repository: @repository, limit: 10)
    end

    test "limits result count" do
      create(:commit_contribution_summary, repository: @repository, user: @user, year: 2022, counts: [42])
      create(:commit_contribution_summary, repository: @repository, user: @contributor, year: 2022, counts: [0, 42])

      assert_equal [@contributor.id], CommitContributionSummary.contributed_user_ids_by_recency(repository: @repository, limit: 1)
    end
  end

  context "ContributionIterator" do
    test "iterates over a boundless date range" do
      contribution_dates = [
        Date.new(2022, 1, 1),
        Date.new(2022, 6, 1),
        Date.new(2022, 12, 1),
        Date.new(2023, 1, 1),
        Date.new(2023, 6, 1),
        Date.new(2023, 12, 1),
      ]
      other_repo = create(:repository, owner: @user)

      contribution_dates.group_by(&:year).each do |year, dates|
        counts = dates.each_with_object(Array.new(365, 0)) { |date, counts| counts[date.yday - 1] = 42 }
        create(:commit_contribution_summary, repository: @repository, user: @user, year: year, counts: counts)
        create(:commit_contribution_summary, repository: other_repo, user: @user, year: year, counts: counts)
        create(:commit_contribution_summary, repository: @repository, user: @contributor, year: year, counts: counts)
      end

      scope = CommitContributionSummary.for_user(@user).order(:year)
      iterator = CommitContributionSummary::ContributionIterator.new(scope)

      assert_equal contribution_dates.size * 2, iterator.count
      assert_equal contribution_dates, iterator.select { |c| c.repository == @repository }.map(&:committed_date)
      assert_equal contribution_dates, iterator.select { |c| c.repository == other_repo }.map(&:committed_date)
    end

    test "iterates over a beginless date range" do
      contribution_dates = [
        Date.new(2022, 1, 1),
        Date.new(2022, 6, 1),
        Date.new(2022, 12, 1),
        Date.new(2023, 1, 1),
        Date.new(2023, 6, 1),
        Date.new(2023, 12, 1),
      ]
      other_repo = create(:repository, owner: @user)

      contribution_dates.group_by(&:year).each do |year, dates|
        counts = dates.each_with_object(Array.new(365, 0)) { |date, counts| counts[date.yday - 1] = 42 }
        create(:commit_contribution_summary, repository: @repository, user: @user, year: year, counts: counts)
        create(:commit_contribution_summary, repository: other_repo, user: @user, year: year, counts: counts)
        create(:commit_contribution_summary, repository: @repository, user: @contributor, year: year, counts: counts)
      end

      scope = CommitContributionSummary.for_user(@user).order(:year)
      iterator = CommitContributionSummary::ContributionIterator.new(scope, ..Date.new(2023, 6, 1))

      assert_equal (contribution_dates.size - 1) * 2, iterator.count
      assert_equal contribution_dates[0..4], iterator.select { |c| c.repository == @repository }.map(&:committed_date)
      assert_equal contribution_dates[0..4], iterator.select { |c| c.repository == other_repo }.map(&:committed_date)
    end

    test "iterates over an endless date range" do
      contribution_dates = [
        Date.new(2022, 1, 1),
        Date.new(2022, 6, 1),
        Date.new(2022, 12, 1),
        Date.new(2023, 1, 1),
        Date.new(2023, 6, 1),
        Date.new(2023, 12, 1),
      ]
      other_repo = create(:repository, owner: @user)

      contribution_dates.group_by(&:year).each do |year, dates|
        counts = dates.each_with_object(Array.new(365, 0)) { |date, counts| counts[date.yday - 1] = 42 }
        create(:commit_contribution_summary, repository: @repository, user: @user, year: year, counts: counts)
        create(:commit_contribution_summary, repository: other_repo, user: @user, year: year, counts: counts)
        create(:commit_contribution_summary, repository: @repository, user: @contributor, year: year, counts: counts)
      end

      scope = CommitContributionSummary.for_user(@user).order(:year)
      iterator = CommitContributionSummary::ContributionIterator.new(scope, Date.new(2022, 2, 1)..)

      assert_equal (contribution_dates.size - 1) * 2, iterator.count
      assert_equal contribution_dates[1..5], iterator.select { |c| c.repository == @repository }.map(&:committed_date)
      assert_equal contribution_dates[1..5], iterator.select { |c| c.repository == other_repo }.map(&:committed_date)
    end
  end

  def leap_year
    2024
  end

  def non_leap_year
    2023
  end

  def sample_counts
    Array.new(365, 42)
  end

  class TestThrottler
    def initialize(before_throttle:)
      @before_throttle = before_throttle
    end

    def throttle
      @before_throttle.call
      yield
    end
  end
end
