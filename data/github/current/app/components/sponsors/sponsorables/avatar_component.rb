# typed: true
# frozen_string_literal: true

# Public: Render the sponsorable's avatar.
class Sponsors::Sponsorables::AvatarComponent < Primer::Component
  DEFAULT_SIZE = 40
  ALLOWED_SIZES = Primer::Beta::Avatar::SIZE_OPTIONS

  def initialize(sponsors_listing:, size: DEFAULT_SIZE, **system_arguments)
    @sponsors_listing = sponsors_listing
    @size = fetch_or_fallback(ALLOWED_SIZES, size, DEFAULT_SIZE)
    @system_arguments = system_arguments
  end

  def call
    render GitHub::AvatarComponent.new(
      size: size,
      src: sponsors_listing.sponsorable_primary_avatar_url(size * 2),
      alt: @system_arguments[:alt] || "@#{sponsorable_login}",
      is_user: sponsors_listing.for_user?,
      **@system_arguments,
    )
  end

  private

  attr_reader :sponsors_listing, :size

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    sponsors_listing.present?
  end
end
