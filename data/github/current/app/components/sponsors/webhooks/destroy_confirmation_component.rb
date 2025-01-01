# typed: strict
# frozen_string_literal: true

class Sponsors::Webhooks::DestroyConfirmationComponent < ApplicationComponent
  extend T::Sig

  ID_PREFIX = "hook-destroy-confirmation-"

  sig { params(sponsors_listing: SponsorsListing, hook: Hook).void }
  def initialize(sponsors_listing:, hook:)
    @sponsors_listing = sponsors_listing
    @hook             = hook
  end

  sig { params(hook: Hook).returns(String) }
  def self.show_dialog_id_for(hook)
    ID_PREFIX + hook.id.to_s
  end

  private

  sig { returns(SponsorsListing) }
  attr_reader :sponsors_listing

  sig { returns(Hook) }
  attr_reader :hook

  sig { returns(T::Boolean) }
  def render?
    hook.persisted?
  end

  sig { returns(String) }
  def dialog_id
    self.class.show_dialog_id_for(hook)
  end

  sig { returns(String) }
  def form_url
    sponsorable_dashboard_webhook_path(sponsors_listing.sponsorable_login, hook.id)
  end
end
