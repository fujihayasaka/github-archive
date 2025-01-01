# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::NextStepsComponent < ApplicationComponent
  include SvgHelper
  include SponsorsButtonsHelper

  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  delegate :for_organization?, :sponsorable, :sponsorable_login, to: :sponsors_listing

  def render?
    sponsors_listing&.approved?
  end

  def profile_type
    for_organization? ? "organization" : "user"
  end

  memoize def funding_file_repo
    sponsorable.global_health_files_repository
  end

  memoize def funding_file_enabled?
    if repo = funding_file_repo
      repo.repository_funding_links_enabled? && repo.has_funding_file?
    end
  end

  memoize def funding_yml_edit_url
    if repo = funding_file_repo
      blob_edit_path(repo.funding_links_path, repo.default_branch, repo)
    end
  end

  def social_default_text
    unless for_organization?
      return "My GitHub Sponsors profile is live! You can sponsor me to support my open source work 💖"
    end
    "#{sponsorable_login}'s GitHub Sponsors profile is live! You can sponsor us to support #{sponsorable_login}'s open source work 💖"
  end
end
