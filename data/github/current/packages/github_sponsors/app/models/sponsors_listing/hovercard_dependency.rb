# typed: true
# frozen_string_literal: true

module SponsorsListing::HovercardDependency
  extend ActiveSupport::Concern

  include UserHovercard::SubjectDefinition

  def user_hovercard_parent
  end

  included do
    # rubocop:disable Lint/UnusedBlockArgument
    define_user_hovercard_context :your_sponsor, ->(user, viewer, descendant_subjects:) do
      # When choosing a Sponsors tier, we let you see a preview of how the sponsorable would
      # start to see your hovercard, and how it would show 'Your sponsor' to that sponsorable.
      # So if the requested user is the same as the viewer, act as if there's a sponsorship,
      # for preview purposes.
      if GitHub.sponsors_enabled? && user == viewer
        UserHovercard::Contexts::YourSponsor.new(private_sponsor: false, related_org_sponsors: [])
      end
    end
  end
  # rubocop:enable Lint/UnusedBlockArgument
end
