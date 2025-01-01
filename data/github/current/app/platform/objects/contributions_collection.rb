# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class ContributionsCollection < Platform::Objects::Base
      description "A contributions collection aggregates contributions such as opened issues and commits created by a user."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # No special API permissions
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.viewer.nil? || object.viewer == permission.viewer
      end


      scopeless_tokens_as_minimum

      # Users can specify the maximum number of repositories to fetch when getting contributions
      # grouped by repositories. What's the biggest maximum they can specify?
      MAX_MAX_REPOSITORIES = 100

      field :user, User, description: "The user who made the contributions in this collection.",
        null: false

      field :started_at, Scalars::DateTime,
        description: "The beginning date and time of this collection.", null: false

      field :ended_at, Scalars::DateTime,
        description: "The ending date and time of this collection.", null: false

      field :has_any_contributions, Boolean, null: false,
        description: "Determine if there are any contributions in this collection.",
        method: :any_contribution?

      field :has_activity_in_the_past, Boolean, null: false,
        description: "Does the user have any more activity in the timeline that occurred prior " \
                     "to the collection's time range?", method: :has_activity_in_the_past?

      field :has_any_restricted_contributions, Boolean, null: false,
        description: "Determine if the user made any contributions in this time frame whose details are not visible because they were made in a private repository. Can only be true if the user enabled private contribution counts.",
        method: :any_restricted_contribution?

      field :enterprise_contributions_user_profile_url, Scalars::URI, null: true,
        description: "The URL of the GitHub Enterprise profile for the user on the installation " \
                     "that sent the first contribution count.",
        method: :async_enterprise_contributions_user_profile_url, visibility: :under_development

      field :restricted_contributions_count, Int, null: false,
        description: "A count of contributions made by the user that the viewer cannot access. Only non-zero when the user has chosen to share their private contribution counts."

      field :earliest_restricted_contribution_date, Scalars::Date, null: true,
        description: "The date of the first restricted contribution the user made in this time period. Can only be non-null when the user has enabled private contribution counts."

      field :latest_restricted_contribution_date, Scalars::Date, null: true,
        description: "The date of the most recent restricted contribution the user made in this time period. Can only be non-null when the user has enabled private contribution counts."

      field :earliest_enterprise_contribution_date, Scalars::Date, null: true,
        description: "The date of the first GitHub Enterprise contribution the user made in this time period.", visibility: :under_development

      field :latest_enterprise_contribution_date, Scalars::Date, null: true,
        description: "The date of the most recent GitHub Enterprise contribution the user made in this time period.", visibility: :under_development

      field :contribution_counts, [ContributionCount], null: false,
        description: "The breakdown of this user's contributions by type of contribution."

      field :is_single_day, Boolean, null: false, method: :single_day?,
        description: "Whether or not the collector's time span is all within the same day."

      field :enterprise_contributions, Connections::EnterpriseContribution,
        null: false,
        visibility: :internal,
        description: "A list of contributions the user made on GitHub Enterprise, aggregated per GitHub Enterprise installation."

      def enterprise_contributions
        ArrayWrapper.new(@object.enterprise_contributions)
      end

      field :issue_contributions, Connections.define(Objects::CreatedIssueContribution),
        null: false,
        description: "A list of issues the user opened." do
        argument :exclude_first, Boolean,
          "Should the user's first issue ever be excluded from the result.",
          default_value: false, required: false
        argument :exclude_popular, Boolean,
          "Should the user's most commented issue be excluded from the result.",
          default_value: false, required: false
        argument :order_by, Inputs::ContributionOrder,
          "Ordering options for contributions returned from the connection.", required: false,
          default_value: { direction: "DESC" }
      end

      def issue_contributions(exclude_first:, exclude_popular:, order_by: nil)
        contributions = @object.issue_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular)
        contributions.reverse! if order_by[:direction] == "ASC"
        ArrayWrapper.new(contributions)
      end

      field :repository_contributions, Connections.define(Objects::CreatedRepositoryContribution),
        null: false,
        description: "A list of repositories owned by the user that the user created in this time range." do
        argument :exclude_first, Boolean,
          "Should the user's first repository ever be excluded from the result.",
          default_value: false, required: false
        argument :order_by, Inputs::ContributionOrder,
          "Ordering options for contributions returned from the connection.", required: false,
          default_value: { direction: "DESC" }
      end

      def repository_contributions(exclude_first:, order_by: nil)
        contributions = @object.repository_contributions(exclude_first: exclude_first)
        contributions.reverse! if order_by[:direction] == "ASC"
        ArrayWrapper.new(contributions)
      end

      field :repository_contribution_counts, Connections.define(Objects::RepositoryContributionCount),
        description: "A list of repositories ordered by (and including) the contribution counts.",
        null: false, visibility: :under_development

      def repository_contribution_counts
        ArrayWrapper.new(@object.repository_contribution_counts)
      end

      field :contribution_years, [Integer], null: false,
        description: "The years the user has been making contributions with the most recent year first."

      field :total_commit_contributions, Integer, method: :total_contributed_commits, null: false,
        description: "How many commits were made by the user in this time span."

      field :joinedGitHubContribution, JoinedGitHubContribution, null: true, method: :joined_github_contribution,
        description: "When the user signed up for GitHub. This will be null if that sign up " \
                     "date falls outside the collection's time range and ignoreTimeRange is " \
                     "false."

      field :first_repository_contribution, Unions::CreatedRepositoryOrRestrictedContribution,
        null: true,
        description: "The first repository the user created on GitHub. This will be null if " \
                     "that first repository was created outside the collection's time range " \
                     "and ignoreTimeRange is false. If the repository is not visible, then a " \
                     "RestrictedContribution is returned."

      field :first_issue_contribution, Unions::CreatedIssueOrRestrictedContribution, null: true,
        description: "The first issue the user opened on GitHub. This will be null if that " \
                     "issue was opened outside the collection's time range and " \
                     "ignoreTimeRange is false. If the issue is not visible but the user has " \
                     "opted to show private contributions, a RestrictedContribution will be " \
                     "returned."

      field :first_pull_request_contribution, Unions::CreatedPullRequestOrRestrictedContribution,
        null: true,
        description: "The first pull request the user opened on GitHub. This will be null if " \
                     "that pull request was opened outside the collection's time range " \
                     "and ignoreTimeRange is not true. If the pull request is not visible but " \
                     "the user has opted to show private contributions, " \
                     "a RestrictedContribution will be returned."

      field :popular_issue_contribution, CreatedIssueContribution, null: true,
        description: <<~DESCRIPTION
          The issue the user opened on GitHub that received the most comments in the specified
          time frame.
        DESCRIPTION

      field :popular_pull_request_contribution, CreatedPullRequestContribution, null: true,
        description: <<~DESCRIPTION
          The pull request the user opened on GitHub that received the most comments in the
          specified time frame.
        DESCRIPTION

      field :contribution_calendar, ContributionCalendar,
        description: "A calendar of this user's contributions on GitHub.", null: false do
        argument :sample, Boolean, default_value: false, required: false,
          description: "Use sample data instead of the user's actual contributions.",
          visibility: :internal
      end

      def contribution_calendar(**arguments)
        if arguments[:sample]
          Contribution::CalendarSample.new
        else
          Contribution::Calendar.new(collector: @object)
        end
      end

      field :most_recent_collection_with_activity, ContributionsCollection, null: true,
        description: <<~DESCRIPTION
          When this collection's time range does not include any activity from the user, use this
          to get a different collection from an earlier time range that does have activity.
        DESCRIPTION

      def most_recent_collection_with_activity
        fetcher = @object.prior_activity_fetcher
        fetcher.collector_with_activity
      end

      field :most_recent_collection_without_activity, ContributionsCollection, null: true,
        description: <<~DESCRIPTION
          Returns a different contributions collection from an earlier time range than this one
          that does not have any contributions.
        DESCRIPTION

      def most_recent_collection_without_activity
        fetcher = @object.prior_activity_fetcher
        fetcher.collector_without_activity
      end

      field :most_recent_collection, ContributionsCollection, null: true, visibility: :internal,
        description: <<~DESCRIPTION
          Returns a contributions collection from an earlier time range than this one
          with contributions if it can find one, or a collection with no activity.
        DESCRIPTION

      def most_recent_collection
        fetcher = @object.prior_activity_fetcher
        fetcher.collector_with_activity || fetcher.collector_without_activity
      end

      field :does_end_in_current_month, Boolean, null: false,
        method: :ends_in_current_month?, description: <<~DESCRIPTION
          Determine if this collection's time span ends in the current month.
        DESCRIPTION

      field :does_start_in_prior_year, Boolean, null: false, visibility: :under_development,
        method: :starts_in_prior_year?, description: <<~DESCRIPTION
          Determine if this collection's time span starts before the current year.
        DESCRIPTION

      field :pull_request_review_contributions,
        Connections.define(Objects::CreatedPullRequestReviewContribution),
        null: false,
        description: <<~DESCRIPTION do
          Pull request review contributions made by the user. Returns the most recently
          submitted review for each PR reviewed by the user.
        DESCRIPTION
        argument :order_by, Inputs::ContributionOrder,
          "Ordering options for contributions returned from the connection.", required: false,
          default_value: { direction: "DESC" }
      end

      def pull_request_review_contributions(order_by: nil)
        contributions = @object.pull_request_review_contributions
        contributions.reverse! if order_by[:direction] == "ASC"
        ArrayWrapper.new(contributions)
      end

      field :pull_request_review_contributions_by_repository,
        [PullRequestReviewContributionsByRepository],
        null: false,
        description: "Pull request review contributions made by the user, grouped by repository." do
        argument :max_repositories, Int, default_value: 25, required: false,
          description: "How many repositories should be included."
      end

      def pull_request_review_contributions_by_repository(max_repositories:)
        if max_repositories > MAX_MAX_REPOSITORIES
          raise Errors::ArgumentLimit,
            "Only up to #{MAX_MAX_REPOSITORIES} repositories is supported."
        end

        @object.pull_request_review_contributions_by_repository(max_repos: max_repositories)
      end

      field :commit_contributions_by_repository, [CommitContributionsByRepository],
        null: false, description: "Commit contributions made by the user, grouped by repository." do
        argument :max_repositories, Int, default_value: 25, required: false,
          description: "How many repositories should be included."
      end

      def commit_contributions_by_repository(max_repositories:)
        if max_repositories > MAX_MAX_REPOSITORIES
          raise Errors::ArgumentLimit,
            "Only up to #{MAX_MAX_REPOSITORIES} repositories is supported."
        end

        @object.commit_contributions_by_repository(max_repos: max_repositories)
      end

      field :pull_request_contributions, Connections.define(Objects::CreatedPullRequestContribution),
        null: false, description: "Pull request contributions made by the user." do
          argument :exclude_first, Boolean,
            "Should the user's first pull request ever be excluded from the result.",
            default_value: false, required: false
          argument :exclude_popular, Boolean,
            "Should the user's most commented pull request be excluded from the result.",
            default_value: false, required: false
          argument :order_by, Inputs::ContributionOrder,
            "Ordering options for contributions returned from the connection.", required: false,
            default_value: { direction: "DESC" }
        end

      def pull_request_contributions(exclude_first:, exclude_popular:, order_by: nil)
        contributions = @object.pull_request_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular)
        contributions.reverse! if order_by[:direction] == "ASC"
        ArrayWrapper.new(contributions)
      end

      field :pull_request_contributions_by_repository,
        [PullRequestContributionsByRepository], null: false,
        description: "Pull request contributions made by the user, grouped by repository." do
          argument :max_repositories, Int, default_value: 25, required: false,
            description: "How many repositories should be included."
          argument :exclude_first, Boolean,
            "Should the user's first pull request ever be excluded from the result.",
            default_value: false, required: false
          argument :exclude_popular, Boolean,
            "Should the user's most commented pull request be excluded from the result.",
            default_value: false, required: false
        end

      def pull_request_contributions_by_repository(max_repositories:, exclude_first:,
                                                   exclude_popular:)
        if max_repositories > MAX_MAX_REPOSITORIES
          raise Errors::ArgumentLimit,
            "Only up to #{MAX_MAX_REPOSITORIES} repositories is supported."
        end

        @object.pull_request_contributions_by_repository(max_repos: max_repositories, exclude_first: exclude_first, exclude_popular: exclude_popular)
      end

      field :joined_organization_contributions, Connections.define(Objects::JoinedOrganizationContribution),
        null: false, visibility: :under_development,
        description: "Contributions representing the user joining organizations on GitHub."

      def joined_organization_contributions
        contributions = @object.joined_organization_contributions
        ArrayWrapper.new(contributions)
      end

      field :total_pull_request_review_contributions, Int, null: false,
        description: "How many pull request reviews the user left."

      field :total_pull_request_contributions, Int, null: false,
        description: "How many pull requests the user opened." do
          argument :exclude_first, Boolean,
            "Should the user's first pull request ever be excluded from this count.",
            default_value: false, required: false
          argument :exclude_popular, Boolean,
            "Should the user's most commented pull request be excluded from this count.",
            default_value: false, required: false
        end

      def total_pull_request_contributions(exclude_first:, exclude_popular:)
        @object.total_pull_request_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular)
      end

      field :total_issue_contributions, Int, null: false,
        description: "How many issues the user opened." do
          argument :exclude_first, Boolean,
            "Should the user's first issue ever be excluded from this count.", default_value: false,
            required: false
          argument :exclude_popular, Boolean,
            "Should the user's most commented issue be excluded from this count.",
            default_value: false, required: false
        end

      def total_issue_contributions(exclude_first:, exclude_popular:)
        @object.total_issue_contributions(exclude_first: exclude_first, exclude_popular: exclude_popular)
      end

      field :total_repository_contributions, Int, null: false,
        description: "How many repositories the user created." do
        argument :exclude_first, Boolean,
          "Should the user's first repository ever be excluded from this count.",
          default_value: false, required: false
      end

      def total_repository_contributions(exclude_first:)
        @object.total_repository_contributions(exclude_first: exclude_first)
      end

      field :total_repositories_with_contributed_issues, Int, null: false,
        description: "How many different repositories the user opened issues in." do
          argument :exclude_first, Boolean,
            "Should the user's first issue ever be excluded from this count.", default_value: false,
            required: false
          argument :exclude_popular, Boolean,
            "Should the user's most commented issue be excluded from this count.",
            default_value: false, required: false
        end

      def total_repositories_with_contributed_issues(exclude_first:, exclude_popular:)
        @object.issue_contribution_repo_count(exclude_first: exclude_first, exclude_popular: exclude_popular)
      end

      field :total_repositories_with_contributed_commits, Int, null: false,
        description: "How many different repositories the user committed to.",
        method: :commit_contribution_repo_count

      field :total_repositories_with_contributed_pull_request_reviews, Int, null: false,
        description: "How many different repositories the user left pull request reviews in.",
        method: :pull_request_review_repo_count

      field :total_repositories_with_contributed_pull_requests, Int, null: false,
        description: "How many different repositories the user opened pull requests in." do
          argument :exclude_first, Boolean,
            "Should the user's first pull request ever be excluded from this count.",
            default_value: false, required: false
          argument :exclude_popular, Boolean,
            "Should the user's most commented pull request be excluded from this count.",
            default_value: false, required: false
        end

      def total_repositories_with_contributed_pull_requests(exclude_first:, exclude_popular:)
        @object.pull_request_contribution_repo_count(exclude_first: exclude_first, exclude_popular: exclude_popular)
      end

      field :issue_contributions_by_repository, [IssueContributionsByRepository],
        null: false,
        description: "Issue contributions made by the user, grouped by repository." do
        argument :max_repositories, Int, default_value: 25, required: false,
          description: "How many repositories should be included."
        argument :exclude_first, Boolean,
          "Should the user's first issue ever be excluded from the result.", default_value: false,
          required: false
        argument :exclude_popular, Boolean,
          "Should the user's most commented issue be excluded from the result.",
          default_value: false, required: false
      end

      def issue_contributions_by_repository(max_repositories:, exclude_first:, exclude_popular:)
        if max_repositories > MAX_MAX_REPOSITORIES
          raise Errors::ArgumentLimit,
            "Only up to #{MAX_MAX_REPOSITORIES} repositories is supported."
        end

        @object.issue_contributions_by_repository(max_repos: max_repositories,
                                                        exclude_first: exclude_first,
                                                        exclude_popular: exclude_popular)
      end
    end
  end
end
