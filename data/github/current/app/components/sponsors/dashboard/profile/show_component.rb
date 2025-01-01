# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::ShowComponent < ApplicationComponent
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  delegate :sponsorable_login, to: :sponsors_listing

  # This VarnishHelper method calls out to ApplicationController::AuthenticityTokenDependency#authenticity_token_for,
  # which is currently out of scope for components, so we need to delegate.
  #
  # IntroductionComponent delegates to :helpers, which is us, and we need to delegate
  # to the actual helpers.
  delegate :csrf_hidden_input_for, to: :helpers

  def render?
    sponsors_listing.present?
  end
end
