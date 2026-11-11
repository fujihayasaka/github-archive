# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Goals::ExamplesComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  def render?
    return false unless logged_in?
    sponsors_listing.present? && !sponsors_listing.disabled?
  end

  memoize def collapsed?
    sponsors_listing.goals.exists?
  end

  def examples
    [
      {
        avatar: image_path("modules/site/sponsors/snowtocat.png"),
        login: "@snowtocat",
        goal_title: "have 10 sponsors",
        goal_description: "It would mean the world to me if I had 10 sponsors. 💖",
      },
      {
        avatar: image_path("modules/site/sponsors/jetpacktocat.png"),
        login: "@jetpacktocat",
        goal_title: "earn $50 per month",
        goal_description: "I'll be able to cover my server costs once I'm sponsored " \
                          "for $50 each month!",
      },
      {
        avatar: image_path("modules/site/sponsors/dinocat.png"),
        login: "@dinocat",
        goal_title: "earn $5,000 per month",
        goal_description: "I'll be able to quit my job and work on open source full time!",
      },
    ]
  end
end
