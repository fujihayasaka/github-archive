# typed: false
# frozen_string_literal: true

# Common methods shared by controllers that deal with user lists.
module UserListsControllerMethods
  extend ActiveSupport::Concern

  included do
    before_action :require_this_user
  end

  # Filters

  # Public: Ensure that the user specified by the `/stars/:user/...` bit of the URL exists.
  def require_this_user
    render_404 unless this_user
  end

  # Public: Ensure that the user making the request is the same as the user specified by the `/stars/:user/...` bit of the URL.
  def require_same_user
    if this_user != current_user
      if request.xhr?
        head :forbidden
      else
        render_404
      end
    end
  end

  # Memoized accessors

  # The user specified by the `/stars/:user/...` bit of the URL. Returns `nil` if no user exists with that login.
  def this_user
    return @this_user if defined?(@this_user)
    @this_user = if GitHub::UTF8.valid_unicode3?(params[:user])
      User.find_by_login(params[:user])
    end
  end

  # The Repository identified by the ?repository_id= parameter in the URL, if one is given and if it is visible to
  # the requesting user.
  def repository
    return @repository if defined?(@repository)
    @repository = if params.has_key?(:repository_id)
      begin
        repo = Repositories::Public.find_active!(params[:repository_id])
        repo.readable_by?(current_user) ? repo : nil
      rescue ActiveRecord::RecordNotFound
        nil
      end
    end
  end
end
