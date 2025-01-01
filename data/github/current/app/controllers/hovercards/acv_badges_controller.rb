# typed: true
# frozen_string_literal: true

class Hovercards::AcvBadgesController < ApplicationController
  include Hovercards::ConditionalAccessMethods

  before_action :require_xhr

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    return render_404 unless this_user && can_have_badge?
    render "hovercards/acv_badges/show", locals: {
      user: this_user,
      contribution_count: contribution_count,
      top_repositories: top_repositories,
      show_repositories: show_repositories?,
    }, layout: false
  end

  private

  memoize def this_user
    User.find_by(type: "User", login: params[:user_id])
  end

  def can_have_badge?
    this_user.can_have_acv_badge?
  end

  def contribution_count
    this_user.acv_contribution_count
  end

  def top_repositories
    this_user.top_acv_repositories
  end

  def show_repositories?
    top_repositories.length > 0 && this_user.block_count <= User::ProfilesDependency::BLOCKERS_AND_BLOCKEES_LIMIT
  end

  def two_factor_enforceable
    return :no if action_name == "show"
    :yes
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
