# typed: true
# frozen_string_literal: true

class Users::Controller < ApplicationController
  def require_this_user
    render_404 unless this_user
  end

  memoize def this_user
    if params[:user_id] && GitHub::UTF8.valid_unicode3?(params[:user_id])
      User.find_by(login: params[:user_id])
    end
  end
  helper_method :this_user
end
