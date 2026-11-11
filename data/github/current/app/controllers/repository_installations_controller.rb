# typed: true
# frozen_string_literal: true

class RepositoryInstallationsController < AbstractRepositoryController
  include IntegrationInstallationsControllerMethods

  PAGE_SIZE = 10

  layout "repository"
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:index]

  def index
    unless current_user.feature_flag_enabled_or_raise?(:fast_repository_installations) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      return super
    end

    installations = repository_installations

    GitHub::PrefillAssociations.prefill_associations(installations, [
      :integration_install_trigger, { integration: [:owner] }
    ])

    render "repository_installations/index", locals: { installations: installations }
  end

  private

  def repository_installations
    base_query = IntegrationInstallation.
      with_repository(current_repository).
      user_installable

    # 1. Pluck (id, integration_id) pairs — no JOIN, no cross-cluster query
    install_pairs = base_query.pluck(:id, :integration_id)

    # 2. Get authoritative sort order from MySQL using the database's utf8mb4_unicode_ci collation.
    #    This is a single-table query against the integrations cluster — no cross-cluster JOIN.
    integration_ids = install_pairs.map(&:last).uniq
    sorted_integration_ids = Integration.where(id: integration_ids).order(:name, :id).pluck(:id)

    # 3. Build a position map for integration ordering
    integration_order = sorted_integration_ids.each_with_index.to_h

    # 4. Filter out installations whose integration was not found (replicates INNER JOIN behavior)
    #    and sort by integration name order (with installation id tiebreaker)
    sorted_ids = install_pairs
      .select { |_id, integration_id| integration_order.key?(integration_id) }
      .sort_by { |id, integration_id| [integration_order[integration_id], id] }
      .map(&:first)

    # 5. Paginate the sorted ID list and load only the current page's full records
    WillPaginate::Collection.create(current_page, PAGE_SIZE, sorted_ids.length) do |pager|
      page_ids = sorted_ids[pager.offset, pager.per_page] || []
      page_records = base_query.where(id: page_ids).to_a

      order_map = page_ids.each_with_index.to_h
      page_records.sort_by! { |inst| order_map[inst.id] || 0 }

      pager.replace(page_records)
    end
  end

  def current_context
    current_repository
  end

  def target_for_conditional_access
    current_repository.owner
  end

  # Set up as a before_action in RepositoryControllerMethods.
  # Overloaded so installations aren’t visible to people who can pull public repos.
  def privacy_check
    return true if current_repository.adminable_by? current_user

    if logged_in? && current_user.site_admin?
      render "admin/locked_repo"
    else
      render_404
    end
  end
end
