# typed: true
# frozen_string_literal: true

module ApplicationController::SkipRcDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  def skip_rc_check
    if params[:skiprc] || request.env["HTTP_X_SKIP_RC"]
      skip_remote_cache
    end
  end

  private

  def skip_remote_cache
    if real_user_site_admin? || employee?
      GH.context.skip_remote_cache = true
    else
      params.delete(:skiprc)
    end
  end
end
