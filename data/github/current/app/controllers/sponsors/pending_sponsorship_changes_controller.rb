# typed: strict
# frozen_string_literal: true

class Sponsors::PendingSponsorshipChangesController < ApplicationController
  include Sponsors::SharedControllerMethods

  before_action :valid_sponsor_required
  before_action :pending_change_required

  sig { void }
  def destroy
    change = T.must_because(pending_change) { "filters eagerly return when not present" }
    if change.cancel(actor: current_user)
      flash[:notice] = "Successfully cancelled pending change."
    else
      flash[:error] = "Sorry, we weren't able to cancel the pending sponsorship change at this time."
    end

    redirect_back(fallback_location: "/")
  end

  private

  sig { returns(T.any(Symbol, GitHubSponsors::Types::Sponsor)) }
  def target_for_conditional_access
    sponsor || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { void }
  def pending_change_required
    render_404 unless pending_change.present?
  end

  sig { returns T.nilable(Sponsorship) }
  memoize def sponsorship
    sponsor&.sponsorship_as_sponsor_for(sponsorable)
  end

  sig { returns T.nilable(Sponsorship::PendingChange) }
  memoize def pending_change
    sponsorship&.pending_change
  end
end
