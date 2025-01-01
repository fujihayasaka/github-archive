# typed: true
# frozen_string_literal: true

class Sponsors::Profile::PinnableReposController < ApplicationController
  include Sponsors::AdminableControllerValidations
  include Sponsors::SharedControllerMethods

  REPOS_PER_PAGE = 20

  before_action :non_waitlisted_sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    respond_to do |format|
      format.html do
        render(
          partial: "sponsors/profiles/pinnable_repos",
          locals: {
            pinnable_items: paginated_repos,
            pinned_items: currently_featured_repos,
            pinned_items_remaining: featured_repos_remaining,
            sponsorable_login: sponsorable&.display_login
          }
        )
      end
    end
  end

  private

  memoize def currently_featured_repos
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    ids = listing.featured_repos.pluck(:featureable_id)
    Repository.where(id: ids)
  end

  memoize def repos_excluding_featured
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    result = Repository.active.owned_by(listing.sponsorable_id)

    if listing.for_user?
      contributed_repo_ids = CommitContributions.domain.contributed_repo_ids(user: T.must(listing.sponsorable), since: 1.year.ago)

      result = result.or(Repository.active.where(id: contributed_repo_ids))
    end

    result
      .public_scope
      .where.not(id: currently_featured_repos.map(&:id))
      .order(::Repository.stargazer_count_column => :DESC)
  end

  memoize def paginated_repos
    repos = currently_featured_repos + repos_excluding_featured
    repos = repos.paginate(page: current_page, per_page: REPOS_PER_PAGE)
    GitHub::PrefillAssociations.prefill_associations(repos, :owner)
    repos
  end

  def featured_repos_remaining
    ::SponsorsListingFeaturedItem::FEATURED_REPOS_LIMIT_PER_LISTING - currently_featured_repos.count
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    sponsorable
  end
end
