# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class Repository::ContributionGraphStatus < ApplicationRecord::Collab
  self.ignored_columns = [:data_source]
  include GitHub::UTF8

  TOP_CONTRIBUTOR_COUNT = 100 # contributors graph only considers the top 100 contributors
  FIRST_WEEK_POST_EPOCH = 259200 # 1970-01-04 00:00:00 UTC

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true

  validates :repository, presence: true

  before_validation :set_initial_viewed_at, on: :create
  def set_initial_viewed_at
    self.last_viewed_at ||= Time.current
  end

  # Public: Finds or creates a graph status record for the given repo.
  #
  # Returns a Repository::ContributionGraphStatus.
  def self.for_repository(repo)
    retry_on_find_or_create_error(max_retry_count: 2) do
      ActiveRecord::Base.connected_to(role: :writing) do
        where(repository: repo).first || create!(repository: repo)
      end
    end
  end

  # Public: Calculates code frequency data for this repository.
  #
  # authenticated: Indicates if the operation is issued in response to an authenticated request.
  #
  # Returns the graph data
  def code_frequency_data(authenticated: false)
    data = insights.fetch_code_frequency_data
    GitHub::RepoGraph::Eventer::CodeFrequency.new(data).to_graph
  end

  # Public: Calculates the contributors graph data for this repository.
  #
  # authenticated: Indicates if the operation is issued in response to an authenticated request.
  #
  # Returns the graph data
  def contributors_data(authenticated: false)
    data = insights.fetch_contributors_data
    GitHub::RepoGraph::Eventer::Contributors.new(data, repository&.enterprise_managed_business).to_graph
  end

  # Public: Calculates commit activiy data for this repository.
  #
  # authenticated: Indicates if the operation is issued in response to an authenticated request.
  #
  # Returns the graph data
  def commit_activity_data(authenticated: false)
    data = insights.fetch_commit_activity_data
    GitHub::RepoGraph::Eventer::CommitActivity.new(data).to_graph
  end

  private

  def insights
    return @insights if defined?(@insights)
    @insights = GitHub::RepoGraph::ContributionInsights.new(repository)
  end
end
