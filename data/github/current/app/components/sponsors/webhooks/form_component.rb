# typed: strict
# frozen_string_literal: true

class Sponsors::Webhooks::FormComponent < ApplicationComponent
  sig { params(sponsors_listing: SponsorsListing, hook: Hook).void }
  def initialize(sponsors_listing:, hook:)
    @sponsors_listing = sponsors_listing
    @hook             = hook
  end

  private

  sig { returns(SponsorsListing) }
  attr_reader :sponsors_listing

  sig { returns(Hook) }
  attr_reader :hook

  sig { returns(String) }
  def form_url
    if hook.new_record?
      sponsorable_dashboard_webhooks_path(sponsors_listing.sponsorable_login)
    else
      sponsorable_dashboard_webhook_path(sponsors_listing.sponsorable_login, hook.id)
    end
  end

  sig { returns(Symbol) }
  def form_method
    hook.new_record? ? :post : :put
  end

  sig { returns(String) }
  def submit_label
    hook.new_record? ? "Create webhook" : "Update webhook"
  end
end
