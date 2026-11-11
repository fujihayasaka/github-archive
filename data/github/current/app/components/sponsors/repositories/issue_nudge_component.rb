# typed: true
# frozen_string_literal: true

class Sponsors::Repositories::IssueNudgeComponent < ApplicationComponent
  include HovercardHelper

  # repository - the Repository containing the issue where this component is rendered
  def initialize(repository:)
    @repository = repository
    @repo_owner = repository&.owner
  end

  private

  attr_reader :repository, :repo_owner

  def render?
    return false unless GitHub.sponsors_enabled? && repository && logged_in?
    return false unless repository.repository_funding_links_enabled?
    return false if repository.has_any_trade_restrictions?
    return false unless sponsorable
    return false if viewer_represents_sponsorable?
    sponsorable.sponsorable_by?(current_user)
  end

  memoize def sponsorable
    if show_funding_file?
      # If we're showing a modal for funding.yml, we need to load it for the repository's owner
      repo_owner
    else
      # If we're not showing the funding.yml modal, it's because no such file exists or it contains only a single
      # sponsorable, which we should link to, otherwise we can link to the repository's owner:
      funding_links&.lone_sponsorable || repo_owner
    end
  end

  memoize def viewer_represents_sponsorable?
    sponsorable.adminable_by?(current_user)
  end

  def sponsor_login_for_link
    # If we're showing this component to the sponsorable themselves, feels weird to link to the page with themselves
    # prefilled as their own sponsor, since we disallow self-sponsorship:
    current_user.display_login unless viewer_represents_sponsorable?
  end

  def sponsorable_login
    sponsorable.display_login
  end

  def repo_name
    repository.name
  end

  memoize def show_funding_file?
    return false unless repository.has_funding_file?
    return false unless funding_links.has_valid_platform?
    return false if repository.funding_links_stafftools_disabled?
    funding_links.has_multiple_sponsorables_or_external_links?
  end

  memoize def funding_links
    repository.funding_links
  end

  def hovercard_attributes
    if sponsorable&.organization?
      safe_data_attributes(hovercard_data_attributes_for_org(login: sponsorable_login))
    else
      safe_data_attributes(hovercard_data_attributes_for_user_login(sponsorable_login))
    end
  end
end
