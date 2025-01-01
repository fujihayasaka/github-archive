# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::IntroductionComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  delegate :csrf_hidden_input_for, to: :helpers

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    sponsors_listing.present?
  end

  def owner
    if sponsorable_login == current_user&.login
      "your"
    else
      "the #{sponsorable_login}"
    end
  end

  memoize def full_description
    begin
      params.dig(:sponsors_listing, :full_description) ||
        sponsors_listing.full_description ||
        full_description_placeholder
    end
  end

  def full_description_placeholder
    <<~FD
      Don’t forget to delete this placeholder text 🙃

      Here are some ideas of what you can tell your potential sponsors:
      - [ ] Who are you, and where are you from?
      - [ ] What are you working on?
      - [ ] Why is their sponsorship important? How will you use the funds?

      Hint: You can include images and emojis in your bio!
    FD
  end
end
