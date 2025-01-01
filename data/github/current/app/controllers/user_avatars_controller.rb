# typed: true
# frozen_string_literal: true

class UserAvatarsController < ApplicationController
  set_statsd_sample_rate 0.01, only: :show

  include MinimalApplicationDependency

  before_action :ensure_user_visible, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:show]

  def show
    # We're shortcircuiting this for mannequins as it is causing 500s down the line
    return render_404 if this_user.mannequin?

    redirect_to this_user.primary_avatar_url(params[:size])
  end

  private

  # Render a 404 if there is no user or the user is hidden from the viewer
  def ensure_user_visible
    return if this_user && !this_user.hide_from_user?(current_user)
    render_404
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_user
  end

  memoize def this_user
    return @user if defined?(@user)
    @user = User.find(params[:user_database_id]) if params[:user_database_id] && params[:user_database_id].to_i.positive?
  end
end
