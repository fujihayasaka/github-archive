# typed: strict
# frozen_string_literal: true

class Orgs::SecurityCenter::CodeScanningAlertGroupsController < Orgs::SecurityCenter::AbstractSecurityCenterController
  include Orgs::SecurityCenter::CodeScanningOrgQueriesHelper
  include CodeScanning::AlertsSerializer
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
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

    results = T.let([], T::Array[Turboscan::Proto::CountsByRepoResponse::RepositoryCounts])

    if query.is_valid?
      # Tenant filtering is performed in the alert query service so the results here are already filtered
      results, has_error, response = alert_query_service.counts_by_repo
    else
      has_error = false
      response = nil
    end

    if has_error
      return render json: {
        message: "Loading code scanning alerts failed",
      }, status: :internal_server_error
    end

    results = T.let(results, T::Array[Turboscan::Proto::CountsByRepoResponse::RepositoryCounts])
    data = T.let(response&.data, T.nilable(Turboscan::Proto::CountsByRepoResponse))

    ordered_repositories_scope = this_organization.repositories.active.order(name: :asc)

    # remove counts not relevant to the query
    results = results.filter do |repo_count|
      (query.open? && repo_count.open_count.nonzero?) || (query.closed? && repo_count.closed_count.nonzero?)
    end if query.open? || query.closed?

    # avoid an empty IN () query when there are no items
    repository_ids = if results.present?
      # avoid a full repository load to start with, just select the IDs in the order we want to display them
      ordered_repositories_scope.where(id: results.map(&:repository_id)).pluck(:id)
    else
      []
    end

    grouped_results = T.let(results.index_by(&:repository_id), T::Hash[Integer, Turboscan::Proto::CountsByRepoResponse::RepositoryCounts])

    cursor = CodeScanning::InMemoryCursor.page(items: repository_ids, after_cursor:, before_cursor:, page_size: per_page)

    groups = if cursor.items.present?
      # fully load the page of repositories
      ordered_repositories_scope.where(id: cursor.items).map do |repository|
        repo_count = grouped_results[repository.id]
        next if repo_count.nil?

        # Calculate the number of alerts actually matching the filter
        alert_count = if query.show_all_states? || !query.has_valid_alert_state?
          repo_count.open_count + repo_count.closed_count
        elsif query.open?
          repo_count.open_count
        elsif query.closed?
          repo_count.closed_count
        else
          repo_count.open_count + repo_count.closed_count
        end

        {
          title: repository.name,
          repositories: [repository.name],
          group: {
            kind: "repository",
            repository: serialized_repository(repository:),
          },
          openCount: repo_count.open_count,
          closedCount: repo_count.closed_count,
          openWithLinksCount: repo_count.open_with_links_count,
          alertCount: alert_count,
        }
      end.compact
    end

    render json: {
      groups: groups || [],
      openCount: data&.open_count || 0,
      closedCount: data&.closed_count || 0,
      nextCursor: cursor.next,
      prevCursor: cursor.prev,
    }
  end

  private

  sig { void }
  def feature_required
    render_404 unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
  end

  sig { void }
  def security_center_required
    render_404 unless SecurityCenter::SecurityFeatures.security_center_available?(this_organization, dotcom_request_only: true)
  end
end
