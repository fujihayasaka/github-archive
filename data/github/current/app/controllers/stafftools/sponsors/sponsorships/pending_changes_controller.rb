# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Sponsorships::PendingChangesController < StafftoolsController
  before_action :require_pending_change

  sig { void }
  def destroy
    change = T.must_because(pending_change) { "filters eagerly return when not present" }
    if change.cancel(actor: current_user)
      flash[:notice] = "Successfully cancelled pending change."
    else
      flash[:error] = "Sorry, we weren't able to cancel the pending sponsorship change at this time."
    end

    redirect_to billing_stafftools_user_path(sponsor)
  end

  private

  sig { void }
  def require_pending_change
    render_404 unless pending_change.present?
  end

  sig { returns T.nilable(GitHubSponsors::Types::Sponsor) }
  def sponsor
    sponsorship&.sponsor
  end

  sig { returns T.nilable(Sponsorship) }
  def sponsorship
    Sponsorship.find_by(id: params[:sponsorship_id])
  end

  sig { returns T.nilable(Sponsorship::PendingChange) }
  memoize def pending_change
    sponsorship&.pending_change
  end
end
