# typed: strict
# frozen_string_literal: true

class Orgs::SponsoringsController < Orgs::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  DEFAULT_PAGE_SIZE = 30

  before_action :sponsors_required

  sig { void }
  def show
    render "orgs/sponsorings/show", locals: {
      organization: this_organization,
      sponsorships: sponsorships,
      dependency_count: dependency_count,
      viewer_is_org_member: viewer_is_member_of_this_org?,
      viewer_can_manage_sponsorships: viewer_can_manage_sponsorships?,
      filter: current_filter,
    }
  end

  private

  sig { returns(T::Boolean) }
  def viewer_can_manage_sponsorships?
    return false unless logged_in?
    current_user.potential_sponsor_ids.include?(this_organization.id)
  end

  sig { returns(T.any(T::Array[Sponsorship], ActiveRecord::Relation)) }
  def sponsorships
    # Preloads and visibility filtering done in `Sponsors::Orgs::SponsoringComponent`:
    this_organization.sponsorships_as_sponsor
  end

  sig { returns(Integer) }
  def dependency_count
    viewer_is_org_admin = this_organization.adminable_by?(current_user)
    return 0 unless viewer_is_org_admin

    only_find_dependencies_from_public_repos = !viewer_is_org_admin
    loader = Repository::OwnerDependenciesLoader.new(
      public_only: only_find_dependencies_from_public_repos,
      owner_id: this_organization.id,
      viewer: current_user,
    )
    loader.total_dependencies
  rescue DependencyGraph::Client::GraphQLError
    0
  end

  sig { returns(Sponsors::Orgs::SponsoringComponent::SponsorshipFilter) }
  def current_filter
    if params[:filter] == Sponsors::Orgs::SponsoringComponent::INACTIVE_FILTER_PARAM
      Sponsors::Orgs::SponsoringComponent::SponsorshipFilter::Inactive
    else
      Sponsors::Orgs::SponsoringComponent::SponsorshipFilter::Active
    end
  end
end
