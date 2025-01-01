# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Tiers::RetireTierButtonComponent < ApplicationComponent
  extend T::Sig

  sig { params(sponsor_count: Integer).void }
  def initialize(sponsor_count:)
    @sponsor_count = sponsor_count
  end

  sig { returns String }
  def call
    render Primer::Beta::Button.new(
      type: :submit,
      test_selector: "retire-tier-button",
      form: "sponsors-retire-tier-form",
      scheme: :link,
      color: :danger,
      "data-confirm": confirmation_message,
    ).with_content("Retire tier")
  end

  private

  sig { returns T::Boolean }
  def render?
    GitHub.sponsors_enabled?
  end

  sig { returns String }
  def confirmation_message
    suffix = if @sponsor_count > 0
      "Existing sponsors will continue to stay on the tier until they update or cancel their sponsorship."
    else
      "You do not have any sponsors on this tier currently."
    end
    "Are you sure you want to retire this tier? Once a tier is retired, it cannot be published again. #{suffix}"
  end
end
