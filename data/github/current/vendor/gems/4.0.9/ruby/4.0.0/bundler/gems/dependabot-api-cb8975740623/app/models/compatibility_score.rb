# frozen_string_literal: true

class CompatibilityScore
  ALLOWED_CI_STATES = [GitHub::CheckRun::Conclusion::SUCCESS, GitHub::CheckRun::Conclusion::FAILURE].freeze
  UPDATED_DEPENDENCIES_INDEX = %w(index_updated_dependencies_on_dependency_details_and_pr_id).freeze

  def initialize(dependency_name:, package_manager:, new_version:, previous_version:)
    @dependency_name = dependency_name
    @package_manager = package_manager
    @new_version = new_version
    @previous_version = previous_version
  end

  def pull_request_counts
    candidate_prs.
      select(:dependabot_commit_ci_status).
      group_by(&:dependabot_commit_ci_status).
      transform_values(&:size)
  end

  private

  attr_reader :dependency_name, :package_manager, :new_version, :previous_version

  def candidate_prs
    ActiveRecord::Base.connected_to(role: :reading) do
      base_query =
        UpdatedDependency.joins(
          "JOIN #{PullRequest.table_name} ON \
                #{PullRequest.table_name}.`id` = #{UpdatedDependency.table_name}.`pull_request_id` \
              JOIN #{Repo.table_name} ON #{Repo.table_name}.`id` = #{PullRequest.table_name}.`repo_id`"
        ).
        where("#{PullRequest.table_name}": pull_request_filters).
        where("#{Repo.table_name}": { private: false }).
        select(updated_dependency_columns).
        where("#{UpdatedDependency.table_name}": dependency_filters).
        optimizer_hints(
          "USE_INDEX(#{UPDATED_DEPENDENCIES_INDEX})",
          "JOIN_ORDER(#{PullRequest.table_name}, #{Repo.table_name})"
        )

      base_query.order("#{UpdatedDependency.table_name}.pull_request_id").limit(250)
    end
  end

  def updated_dependency_columns
    %W(
      #{UpdatedDependency.table_name}.name
      #{UpdatedDependency.table_name}.package_manager
      #{UpdatedDependency.table_name}.version
      #{UpdatedDependency.table_name}.previous_version
      #{UpdatedDependency.table_name}.pull_request_id
    )
  end

  def dependency_filters
    {
      name: dependency_name,
      package_manager: package_manager,
      version: new_version,
      previous_version: previous_version,
    }.compact
  end

  def pull_request_filters
    {
      multiple_dependencies: false,
      base_commit_ci_status: GitHub::CheckRun::Conclusion::SUCCESS,
      dependabot_commit_ci_status: ALLOWED_CI_STATES,
    }.compact
  end
end
