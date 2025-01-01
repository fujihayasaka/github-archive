# typed: strict
# frozen_string_literal: true

class Sponsors::Profile::FeaturedWorksController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  REPOS_PER_PAGE = 20

  before_action :non_waitlisted_sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit], optional: true

  sig { void }
  def edit
    render Sponsors::Dashboard::Profile::SortableFeaturedReposComponent.new(
      featured_repos: selected_repos
    ), layout: false
  end

  sig { void }
  def show
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    render Sponsors::Dashboard::Profile::FeaturedWorkSearchResultsComponent.new(
      currently_featured_repos: currently_featured_repos,
      repositories: paginated_repos,
      sponsorable_login: sponsorable.display_login,
    ), layout: false
  end

  private

  sig { returns T::Array[Repository] }
  memoize def currently_featured_repos
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    ids = T.let(listing.featured_repos.pluck(:featureable_id), T::Array[Integer])
    Repositories::Public.load_repositories(ids).to_a
  end

  sig { returns T::Array[Repository] }
  memoize def repos_excluding_featured
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    repos_excluding_featured = Repository.active.owned_by(listing.sponsorable_id)

    if listing.for_user?
      contributed_repo_ids = CommitContribution
        .for_user(listing.sponsorable_id)
        .where(committed_date: 1.year.ago..Time.zone.now)
        .group(:repository_id)
        .pluck(:repository_id)

      repos_excluding_featured = repos_excluding_featured
        .or(Repositories::Public.load_repositories(contributed_repo_ids))
    end

    repos_excluding_featured
      .public_scope
      .where.not(id: currently_featured_repos.map(&:id))
      .order(::Repository.stargazer_count_column => :DESC)
      .to_a
  end

  sig { returns T::Array[Repository] }
  memoize def paginated_repos
    repos = available_repos.paginate(page: current_page, per_page: REPOS_PER_PAGE)
    GitHub::PrefillAssociations.prefill_associations(repos, :owner)
    repos
  end

  sig { returns(T::Array[Repository]) }
  memoize def available_repos
    currently_featured_repos + repos_excluding_featured
  end

  sig { returns T::Array[Repository] }
  memoize def selected_repos
    selected_repo_ids = featured_repo_ids.map(&:to_i)
    available_repos.select { |repo| selected_repo_ids.include?(repo.id) }
  end

  sig { returns T::Array[T.any(Integer, String)] }
  def featured_repo_ids
    params[:repo_ids] || []
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
