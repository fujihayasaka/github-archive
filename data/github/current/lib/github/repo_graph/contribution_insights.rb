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

      def fetch_contributors_data
        # ignore the emails passed in, it will be blank. Instead find our own list of top contributors
        # provide a viewer for "spam filtering purposes"
        users = repository.top_contributors(limit: 100, viewer: nil)

        history = CommitContributions.domain.repository_contribution_history(repository: repository, users: users)
        {
          COMMITS => history[:commits],
          ADDITIONS => history[:additions],
          DELETIONS => history[:deletions]
        }
      end

      def fetch_commit_activity_data
        {
          COMMITS => CommitContributions.domain.repository_commit_activity(repository: repository)
        }
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
        first_commit_date = CommitContributions.domain.first_repository_contribution_date(repository: repository)

        return 1 if first_commit_date.nil?
        start_time = Time.utc(first_commit_date.year, first_commit_date.month, first_commit_date.day)
        time = Time.now.utc
        end_time = Time.utc(time.year, time.month, time.day)
        total_days = ((end_time - start_time) / 24 / 60 / 60).to_i
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
