# typed: strict
# frozen_string_literal: true

class Users::FollowsController < ApplicationController
  include ActionView::Helpers::NumberHelper
  include T::Sig

  CANT_PERFORM_ERROR_MSG = "You can't perform that action at this time."

  before_action :login_required
  before_action :require_target_user
  before_action :require_unblocked, only: [:create]

  sig { void }
  def create
    if current_user.follow(target_user, context: "user_profile")
      GitHub.dogstats.increment("user", tags: ["action:follow"])
      render_result(success: true)
    else
      render_result(success: false)
    end
  rescue ActiveRecord::RecordInvalid => e
    if e.message.include?(GitHub::RateLimitedCreation::ERROR_MESSAGE)
      render_result(success: false)
    else
      raise
    end
  end

  sig { void }
  def destroy
    current_user.unfollow(target_user, context: "user_profile")
    GitHub.dogstats.increment("user", tags: ["action:unfollow"])
    render_result(success: true)
  end

  private

  sig { returns(T.nilable(User)) }
  memoize def target_user
    if params[:target] && GitHub::UTF8.valid_unicode3?(params[:target])
      User.find_by_login(params[:target])
    end
  end

  sig { params(success: T::Boolean).void }
  def render_result(success:)
    flash[:error] = CANT_PERFORM_ERROR_MSG unless success

    if request.xhr?
      render json: { count: number_with_delimiter(T.must(target_user).followers_count(viewer: current_user)) },
        status: success ? :ok : :unprocessable_entity
    else
      redirect_to :back
    end
  end

  sig { void }
  def require_target_user
    render_404 unless target_user
  end

  sig { void }
  def require_unblocked
    if current_user.blocked_by?(target_user) || T.must(target_user).blocked_by?(current_user)
      render_result(success: false)
    end
  end

  sig { returns(T.any(User, Symbol)) }
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless target_user # rubocop:todo GitHub/SpecifyResourceForConditionalAccess
    T.must(target_user)
  end
end
