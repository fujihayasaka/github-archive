# typed: true
# frozen_string_literal: true

class MoveWork::BaseController < ApplicationController
  before_action :login_required
  before_action :non_emu_required
  before_action :dotcom_required
  before_action :require_ownership_when_is_org

  preload_features [:project_sculk]
  javascript_bundle "move-work"

  private

  memoize def this_organization
    Organization.find_by_login(params[:org])
  end

  def current_context
    this_organization || current_user
  end
  helper_method :current_context

  def require_ownership_when_is_org
    return unless this_organization

    render_404 unless this_organization.adminable_by?(current_user)
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_context
  end

  def move_work_session
    session[:move_work] ||= {}
  end
end
