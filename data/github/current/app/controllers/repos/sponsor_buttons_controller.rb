# typed: true
# frozen_string_literal: true

class Repos::SponsorButtonsController < AbstractRepositoryController
  before_action :require_xhr, only: :show
  before_action :ensure_sponsorable_or_funding_file, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    open_modal = GitHub.sponsors_enabled? && params[:sponsor] == "1"
    if open_modal || has_multiple_sponsorables_or_external_links?
      render Sponsors::Repositories::FundingModalComponent.new(
        owner_login: owner.display_login,
        repo_name: current_repository.name,
        auto_open_url_param: "sponsor",
        is_sponsoring: viewer_is_a_sponsor?,
      ), layout: false
    else
      sponsorable = funding_links&.lone_sponsorable || owner
      is_viewer_sponsoring = is_sponsoring_by_sponsorable_id[sponsorable.id]
      render Sponsors::SponsorButtonComponent.new(
        sponsorable: sponsorable,
        is_sponsoring: is_viewer_sponsoring,
        location: is_viewer_sponsoring ? :REPOSITORY_HEADER_SPONSORING : :REPOSITORY_HEADER_SPONSOR,
      ), layout: false
    end
  end

  private

  def ensure_sponsorable_or_funding_file
    render_404 unless owner.sponsorable? || funding_links.present?
  end

  memoize def funding_links
    current_repository.funding_links
  end

  def has_multiple_sponsorables_or_external_links?
    return false unless funding_links
    funding_links.has_multiple_sponsorables_or_external_links?
  end

  memoize def is_sponsoring_by_sponsorable_id
    return {} unless logged_in?
    sponsor_id = current_user.id
    sponsorable_ids = [owner.id]
    sponsorable_ids += funding_links.sponsorable_ids if funding_links
    sponsoring_checker = Platform::Loaders::IsSponsoringCheck.new(sponsor_id, viewer: current_user)
    sponsoring_checker.fetch(sponsorable_ids)
  end

  def viewer_is_a_sponsor?
    return false unless logged_in?
    is_sponsoring_by_sponsorable_id.any? { |_sponsorable_id, is_sponsoring| is_sponsoring }
  end
end
