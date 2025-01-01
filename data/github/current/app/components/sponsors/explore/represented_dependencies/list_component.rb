# typed: true
# frozen_string_literal: true

class Sponsors::Explore::RepresentedDependencies::ListComponent < ApplicationComponent
  # paginated_repositories - a WillPaginate::Collection of Repository records that are owned or otherwise represented
  #                          by the `sponsorable` User/Organization
  # potential_sponsor - the User or Organization that would sponsor or is sponsoring the `sponsorable` User
  # sponsorable - the String login of the sponsorable User or Organization who owns or represents the specified
  #               repositories, e.g., they're listed in the funding.yml for the repositories
  # filter_set - a SponsorsExploreFilterSet with the currently applied filters and sort order, for URLs
  def initialize(paginated_repositories:, potential_sponsor:, sponsorable:, filter_set: nil)
    @paginated_repositories = paginated_repositories
    @potential_sponsor = potential_sponsor
    @sponsorable = sponsorable
    @filter_set = filter_set || SponsorsExploreFilterSet.new
  end

  private

  attr_reader :potential_sponsor, :sponsorable, :filter_set

  delegate :next_page, to: :paginated_repositories

  def render?
    GitHub.sponsors_enabled? && potential_sponsor.present? && sponsorable.present? &&
      (filter_set.account_login.blank? || filter_set.account_login == potential_sponsor.login) &&
      paginated_repositories.present?
  end

  # Private: Are any of the listed repositories owned by someone other than the sponsorable this modal is about?
  #
  # Returns a Boolean.
  def non_owner_sponsorables_included?
    @paginated_repositories.any? { |repo| repo.owner_login != sponsorable_login }
  end

  memoize def sponsoring?
    sponsorable.sponsor_exists_and_is_visible_to?(potential_sponsor.id, viewer: current_user)
  end

  memoize def sponsorable_login
    sponsorable.login
  end

  # Private: Should we show an informational header section above the results in this page, to give context about
  # what the results are?
  #
  # Returns a Boolean.
  def show_header?
    # Only want to show the header on the first page of results so that we don't interrupt the list of results with
    # a repeat of the header. Each new page of results is inserted into the page replacing the 'Load more' form.
    paginated_repositories.current_page == 1
  end

  memoize def paginated_repositories
    # Used by Stars::ButtonComponent:
    Stars.domain.precache_repos_starred_by_user?(@paginated_repositories.pluck(:id), current_user.id) if current_user
    @paginated_repositories
  end
end
