# typed: false
# frozen_string_literal: true

module Orgs::RepositoryItemsHelper
  include Repositories::Domain::Provider
  include Scientist

  MAX_PAGES = 100
  PER_PAGE = 250

  PER_PAGE_NEW = 100

  # Currently ::Search::Query::max_offset_default is 1000 and we are overriding to get more results
  MAX_OFFSET = 10000

  def additional_repositories(selected_repository_ids, public_only: false)
    total_count = current_organization.repositories.size

    repositories_domain.by_org_excluding(
      organization_id: current_organization.id,
      excluded_repo_ids: selected_repository_ids,
      pagination: GH::Pagination::Offset.new(page: page, per_page: PER_PAGE, validate: false),
      max_pages: MAX_PAGES * PER_PAGE,
      public_only:,
    )
  end

  def ensure_page_specified
    return render_404 unless page && page > 0
  end

  def page
    params[:page].to_i
  end

  def runner_group_policy?
    policy == Orgs::ActionsSettings::RepositoryItemsController::RUNNER_GROUPS_POLICY && policy_id.present?
  end

  def actions_access_policy?
    policy == Orgs::ActionsSettings::RepositoryItemsController::ACCESS_POLICY
  end

  def repo_self_hosted_runners_policy?
    policy == Orgs::ActionsSettings::RepositoryItemsController::REPO_SELF_HOSTED_RUNNERS
  end

  def raw_query
    params[:q] || ""
  end

  def query
    return raw_query if raw_query.include? "org:"

    "org:#{current_organization.name} #{raw_query}"
  end
end
