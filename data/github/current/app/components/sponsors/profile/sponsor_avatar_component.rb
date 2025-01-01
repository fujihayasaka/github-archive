# typed: true
# frozen_string_literal: true

# Public: Renders an avatar for and a link to the `user_or_org`, if the given `sponsorship` is visible to the `current_user`.
# Otherwise, it will render a generic avatar and will not render any identifying information
# (login, link to profile, or avatar).
#
#
# To use this component without introducing N+1s, prefill the necessary method. For example:
#
#   GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :sponsor_readable_by?, current_user)
class Sponsors::Profile::SponsorAvatarComponent < ApplicationComponent
  include AvatarHelper

  # user_or_org - User or Organization whose avatar should be rendered, someone representing either
  #               the sponsor or the sponsorable of the given sponsorship
  # sponsorship - Sponsorship that this avatar represents.
  # size - Integer representing the size of the avatar in pixels.
  # is_first_on_page - Boolean representing whether this is the first in a paginated list. Omit if not paginated.
  # next_page - Integer representing the next page number, or nil. Omit if not paginated.
  # next_page_filter - String representing the filter to use for pagination ("all", "active", "inactive")
  def initialize(user_or_org:, sponsorship:, size:, is_first_on_page: false, next_page: nil, next_page_filter: "all")
    @user_or_org = user_or_org
    @sponsorship = sponsorship
    @next_page = next_page
    @next_page_filter = fetch_or_fallback(Sponsors::SponsorsPartialsController::SPONSORSHIP_PAGINATION_FILTERS, next_page_filter, "all")
    @is_first_on_page = is_first_on_page
    @size = size
  end

  # Public: Prefills the necessary methods for this component to render without N+1 queries.
  #
  # sponsorships - Array of sponsorships to prefill
  # current_user - User who is currently logged in, or nil if no one is logged in.
  #
  # Returns nil
  def self.prefill_necessary_methods(sponsorships, current_user:)
    GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :sponsor_readable_by?, current_user)
    GitHub::PrefillAssociations.prefill_associations(sponsorships, :sponsorable)
    GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :blocked_for?, current_user)
  end

  private

  attr_reader :next_page, :next_page_filter, :size, :user_or_org, :sponsorship
  delegate :sponsorable, :sponsor, to: :sponsorship

  def blocked?
    sponsorship.blocked_for?(current_user)
  end

  def can_show_identity?
    sponsorship.sponsor_readable_by?(current_user) && !blocked?
  end

  def first_on_page?
    @is_first_on_page
  end

  # Private: Returns an attribute used to paginate avatars using `<remote-pagination>`
  #
  # https://github.github.io/web-systems-documentation/#custom-elements-remote-pagination-md
  #
  # The `data-pagination-src` attribute is used by the <remote-pagination>
  # element to determine which URL to call to get the next page of results.
  #
  # The `data-pagination-src` *must* be included if the avatar is the first
  # item on the page and the avatar is part of a paginated collection. Otherwise
  # <remote-pagination> won't know what to load.  If this is the last page, the
  # attribute must still be present, but the value empty. An empty value
  # tells the remote-pagination element that there are no more pages to load.
  def next_page_attribute
    if first_on_page?
      "data-pagination-src=#{next_page_path}"
    end
  end

  def next_page_path
    sponsorable_sponsors_partial_path(sponsorable, page: next_page, filter: next_page_filter) if next_page.present?
  end

  # Private: Returns a uuid used to link an anonymous sponsor avatar to a tooltip
  memoize def private_sponsor_uuid
    "anonymous-sponsor-tooltip-avatar-#{SecureRandom.uuid}"
  end
end
