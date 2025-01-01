# typed: true
# frozen_string_literal: true

# This class is intended to replace GitHub::RepoGraph::Eventer. Instead of using the Eventer client,
# this class uses the CommitContribution table to get the data used for the Insights tabs.
# This affects the Contributors, Commit Activity, and CodeFrequency tabs.
#
# The differences in the data between Eventer and ContributionInsights approaches are:
# 1. Eventer gets data from the git file system. ContributionInsights gets data from CommitContribution table
# 2. Eventer data does not match the repo main page's "Contributors" face pile. ContributionInsights does.
# 3. Eventer has added/deleted lines of code. ContributionInsights does not so we return all zeros.
# 4. Eventer filters out merge commits and bot commits. ContributionInsights includes both.
# 5. Eventer is an external service that is unsupported and at risk of collapse. ContributionInsights is not.

module GitHub
  module RepoGraph
    class ContributionInsights
      include Scientist

      ADDITIONS = "RepoGraphs_Additions"
      DELETIONS = "RepoGraphs_Deletions"
      COMMITS = "RepoGraphs_Commits"

      def initialize(repository)
        @repository = repository
      end

      attr_reader :repository

      def contribution_summaries_available?
        return @contribution_summaries_available if defined?(@contribution_summaries_available)

        @contribution_summaries_available = CommitContributionSummary.for_repository(repository).exists?
      end

      def fetch_contributors_data
        # ignore the emails passed in, it will be blank. Instead find our own list of top contributors
        # provide a viewer for "spam filtering purposes"
        users = repository.top_contributors(limit: 100, viewer: nil)

        science("contribution_summaries_fetch_contributors_data") do |e|
          e.use do
            fetch_contributors_data_control(users: users)
          end

          e.try do
            fetch_contributors_data_candidate(users: users)
          end

          e.run_if { contribution_summaries_available? }

          e.context({
            repository_id: repository.id
          })

          e.clean { |value| value[COMMITS] }
        end
      end

      # Public: Fetches all metrics for the given set of emails in the repository.
      #
      #
      # Returns the data fetched from Eventer.
      def fetch_contributors_data_control(users:)
        all_contributions = CommitContribution.select(:user_id, :committed_date, :commit_count).where(repository: repository, user_id: users.map(&:id))

        all_commits = {}
        all_adds = {}
        all_deletes = {}

        users.each do |user|
          email = user.git_author_email
          next unless email.present?
          user_commits = {}
          user_adds = {}
          user_deletes = {}
          all_contributions.where(user_id: user.id).each do |c|
            timestamp = c.committed_date.to_time.to_i
            user_commits[timestamp] = c.commit_count
            user_adds[timestamp] = 0
            user_deletes[timestamp] = 0
          end
          all_commits[email] = user_commits
          all_adds[email] = user_adds
          all_deletes[email] = user_deletes
        end

        data =
        {
          COMMITS => all_commits,
          ADDITIONS => all_adds,
          DELETIONS => all_deletes
        }
      end

      # Public: Generate a contribution history for the given repository and optional users.
      #
      # repository - The Repository to generate the history for.
      #
      # While running commit contribution summary experiments, optionally accept the list of top
      # contributors so the top_contributors experiment doesn't impact the timing of the contributors_data
      # experiment that's calling this.
      #
      # Returns a Hash of Hashes, in the same format as returned by
      # GitHub::RepoGraph::ContributionInsights#fetch_contributors_data.
      def fetch_contributors_data_candidate(users:)
        CommitContributionSummary.repository_contribution_history(repository: repository, users: users)
      end

      def fetch_commit_activity_data
        science("contribution_summaries_fetch_commit_activity_data") do |e|
          e.use do
            fetch_commit_activity_data_control
          end

          e.try do
            fetch_commit_activity_data_candidate
          end

          e.run_if { contribution_summaries_available? }

          e.context({
            repository_id: repository.id
          })
        end
      end

      # Public: Fetches commit metrics for the last 52 weeks for the repository.
      #
      # Returns the data fetched from Eventer.
      # fetch total daily commits for all users in the repo
      def fetch_commit_activity_data_control
        all_contributions = CommitContribution.select(:committed_date, :commit_count).where(repository: repository, committed_date: 1.year.ago..).group(:committed_date).order(committed_date: :asc).sum(:commit_count)
        all_contributions = T.cast(all_contributions, T::Hash[Date, Integer]).transform_keys { |k| k.to_time.to_i }
        data =
        {
          COMMITS => all_contributions.to_a
        }
      end

      def fetch_commit_activity_data_candidate
        CommitContributionSummary.repository_commit_activity(repository: repository)
      end

      # Public: Fetches all additions and deletions for the repository.
      # In this case it's all zero since CommitContributions doesn't have this data!
      # Stubs a bunch of zeros for each day of the repo's lifetime.
      def fetch_code_frequency_data
        adds = {}
        deletes = {}

        day_timestamps.each do |day|
          adds[day.to_i.to_s] = 0
          deletes[day.to_i.to_s] = 0
        end

        data =
        {
          ADDITIONS => adds,
          DELETIONS => deletes
        }
      end

      def day_timestamps
        time = Time.now.utc
        midnight = Time.utc(time.year, time.month, time.day)
        days = []

        find_day_count_of_repo_lifetime.times do |c|
          days[c] = midnight - c * 24 * 60 * 60
        end
        days
      end

      def find_day_count_of_repo_lifetime
        first_commit_date = science("contribution_summaries_first_commit_date") do |e|
          e.use { CommitContribution.where(repository: repository).order(:committed_date).pluck(:committed_date).first }

          e.try { first_summary_commit_date }

          e.run_if { contribution_summaries_available? }

          e.context({
            repository_id: repository.id
          })
        end

        return 1 if first_commit_date.nil?
        start_time = Time.utc(first_commit_date.year, first_commit_date.month, first_commit_date.day)
        time = Time.now.utc
        end_time = Time.utc(time.year, time.month, time.day)
        total_days = ((end_time - start_time) / 24 / 60 / 60).to_i
      end

      # Public: find the first commit day in the repo's commit contribution summaries
      def first_summary_commit_date
        # We need to check all summaries from the first year they exist for this repo. In general, the earliest
        # created summary will have the earliest commit day, so we check them in that order.
        first_year = CommitContributionSummary.minimum(:year)
        summaries = CommitContributionSummary.for_repository(repository).where(year: first_year).order(:created_at).to_a
        return nil if summaries.empty?

        # CommitContributionSummary records must all have at least one nonzero count, so there will
        # a summary with a contribution on or before the end of the year.
        first_day = T.let(Date.new(first_year, 12, 31).yday, T.untyped)

        summaries.each do |summary|
          summary.counts.each_with_index do |count, day|
            # Early exit if this summary doesn't have an earlier contribution day
            break if day >= first_day

            # Check whether this day should be the new first_day
            if count > 0 && day < first_day
              first_day = day
              break
            end
          end

          # Early exit if one of the summaries had a commit on the first day of the year
          break if first_day == 0
        end

        Date.new(first_year, 1, 1) + first_day.days
      end

      # Public: Indicates if eventer has all the data up to and including the given oid by
      #   checking for the presence of an indexed "marker" event.
      #
      # Returns true if up to date, false if not, and nil if no metrics were ever sent for the repo.
      def up_to_date?(last_indexed_oid)
        true
      end

      # Public: Indicates if data for this repository has ever been fully indexed.
      #
      # Returns a Boolean.
      def has_indexed_data?
        true
      end

      def delete_counters(authenticated: false)
      end
    end
  end
end
