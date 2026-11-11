# typed: true
# frozen_string_literal: true

module Api::App::SkipRcDependency
  extend T::Helpers
  requires_ancestor { Api::App }

  # Internal: Check for the skiprc query parameter or X-Skip-RC header and
  # disable the remote cache for the current request when the caller is a
  # staff member. Non-staff callers have the parameter silently stripped.
  #
  # This mirrors ApplicationController::SkipRcDependency for the Sinatra API
  # layer and is intended for debugging purposes only.
  #
  # Returns nothing.
  def skip_rc_check
    if params[:skiprc] || request.env["HTTP_X_SKIP_RC"]
      skip_remote_cache
    end
  end
  private :skip_rc_check

  private

  def skip_remote_cache
    if current_user&.site_admin? || request_authorized_by_employee?
      GH.context.skip_remote_cache = true
    else
      params.delete("skiprc")
    end
  end
end
