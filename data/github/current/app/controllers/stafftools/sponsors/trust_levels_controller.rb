# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::TrustLevelsController < StafftoolsController
  before_action :sponsors_required

  def update
    success, error_message = set_trust_level

    if success
      flash[:notice] = "Updated trust level"
    else
      flash[:error] = error_message || "Error updating trust level"
    end

    redirect_back(fallback_location: stafftools_user_path(this_user))
  end

  private

  # Private: Persist the user's Sponsors trust level
  #
  # Returns a 2-tuple of [Boolean success, String error_message]
  def set_trust_level
    begin
      if target_type == :sponsor
        Sponsors::TrustLevel.set_as_sponsor(actor: current_user, sponsor: this_user, trust_level: trust_level)
      elsif target_type == :sponsorable
        Sponsors::TrustLevel.set_as_sponsorable(actor: current_user, sponsorable: this_user, trust_level: trust_level)
      else
        return [false, "Invalid target type #{target_type}"]
      end
    rescue Sponsors::TrustLevel::UnprocessableError => error
      [false, error.message]
    else
      [true, nil]
    end
  end

  memoize def trust_level
    params[:trust_level]&.to_sym
  end

  memoize def target_type
    params[:target_type]&.to_sym
  end
end
