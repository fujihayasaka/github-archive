# typed: true
# frozen_string_literal: true

class Sponsors::PotentialSponsorableBannersController < ApplicationController
  before_action :require_sponsors
  before_action :login_required
  before_action :require_potential_sponsorship

  def destroy
    potential_sponsorship.acknowledge!
    current_user.dismiss_notice(PotentialSponsorship::NOTICE)
    if request.xhr?
      head :ok
    else
      redirect_to :back
    end
  end

  private

  def require_sponsors
    render_404 unless GitHub.sponsors_enabled?
  end

  memoize def potential_sponsorable
    user_login = params[:user_id]
    User.find_by_login(user_login)
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless potential_sponsorable # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    potential_sponsorable
  end

  memoize def potential_sponsorship
    potential_sponsorable.potential_sponsorships_as_sponsorable.with_pending_state.find_by(id: params[:id])
  end

  def require_potential_sponsorship
    render_404 unless potential_sponsorship
  end
end
