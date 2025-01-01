# typed: true
# frozen_string_literal: true

# Public: Render the sponsorable's avatar with a link to their user profile page.
class Sponsors::Sponsorables::LinkedAvatarComponent < Primer::Component
  DEFAULT_AVATAR_SIZE = Sponsors::Sponsorables::AvatarComponent::DEFAULT_SIZE
  ALLOWED_AVATAR_SIZES = Sponsors::Sponsorables::AvatarComponent::ALLOWED_SIZES

  def initialize(sponsors_listing:, avatar_size: DEFAULT_AVATAR_SIZE, link_url: nil, **system_arguments)
    @sponsors_listing = sponsors_listing
    @avatar_size = fetch_or_fallback(ALLOWED_AVATAR_SIZES, avatar_size, DEFAULT_AVATAR_SIZE)
    @link_url = link_url
    @system_arguments = system_arguments
  end

  def call
    @system_arguments[:href] = @link_url || user_path(sponsorable_login)
    render Users::ProfileLinkComponent.new(
      login: sponsorable_login,
      is_organization: for_organization?,
      **@system_arguments,
    ) do
      render Sponsors::Sponsorables::AvatarComponent.new(sponsors_listing: sponsors_listing, size: avatar_size)
    end
  end

  private

  attr_reader :sponsors_listing, :avatar_size

  delegate :sponsorable_login, :for_organization?, to: :sponsors_listing

  def render?
    sponsors_listing.present?
  end
end
