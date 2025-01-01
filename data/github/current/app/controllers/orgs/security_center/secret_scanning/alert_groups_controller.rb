# typed: strict
# frozen_string_literal: true

class Orgs::SecurityCenter::SecretScanning::AlertGroupsController < Orgs::SecurityCenter::SecretScanning::AbstractController
  include SecretScanningControllerHelper
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  before_action :organization_read_required
  before_action :feature_required
  before_action :security_center_required

  sig { void }
  def index
    per_page = 10

    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    unless has_repositories?
      return render json: {
        groups: [],
        openCount: 0,
        closedCount: 0,
        nextCursor: nil,
        prevCursor: nil,
      }
    end

    # Tenant filtering is performed in the alert query service so the results here are already filtered
    results, has_error, response_data = alert_query_service.counts_by_repo

    if has_error
      return render json: {
        message: "Loading secret scanning alert groups failed",
      }, status: :internal_server_error
    end

    ordered_repositories_scope = this_organization.repositories.active.order(name: :asc)

    # remove counts not relevant to the query
    results = results.filter do |repo_count|
      (parsed_query.is_open_page? && repo_count.unresolved_count.nonzero?) || (parsed_query.is_closed_page? && repo_count.resolved_count.nonzero?)
    end if parsed_query.is_open_page? || parsed_query.is_closed_page?

    # avoid an empty IN () query when there are no items
    repository_ids = if results.present?
      # avoid a full repository load to start with, just select the IDs in the order we want to display them
      ordered_repositories_scope.where(id: results.map(&:repository_id)).pluck(:id)
    else
      []
    end

    grouped_results = T.let(
      results.index_by(&:repository_id),
      T::Hash[Integer, GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation::RepoCount]
    )

    cursor = CodeScanning::InMemoryCursor.page(items: repository_ids, after_cursor:, before_cursor:, page_size: per_page)

    groups = if cursor.items.present?
      # fully load the page of repositories
      ordered_repositories_scope.where(id: cursor.items).map do |repository|
        repo_count = grouped_results[repository.id]
        next if repo_count.nil?

        # Calculate the number of alerts actually matching the filter
        alert_count = if !parsed_query.has_valid_alert_state?
          repo_count.unresolved_count + repo_count.resolved_count
        elsif parsed_query.is_open_page?
          repo_count.unresolved_count
        elsif parsed_query.is_closed_page?
          repo_count.resolved_count
        else
          repo_count.unresolved_count + repo_count.resolved_count
        end

        {
          title: repository.name,
          repositories: [repository.name],
          group: {
            kind: "repository",
            repository: SecretScanning::SecurityCampaigns::AlertsSerializer.serialized_repository(repository: repository),
          },
          openCount: repo_count.unresolved_count,
          closedCount: repo_count.resolved_count,
          alertCount: alert_count,
        }
      end.compact
    end

    # Calculate totals from service response or aggregated data
    total_open_count = response_data&.try(:unresolved_count) || 0
    total_closed_count = response_data&.try(:resolved_count) || 0

    render json: {
      groups: groups || [],
      openCount: total_open_count,
      closedCount: total_closed_count,
      nextCursor: cursor.next,
      prevCursor: cursor.prev,
    }
  end
end
