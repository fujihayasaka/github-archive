# typed: true
# frozen_string_literal: true

class Hovercards::ProfileHighlightsController < ApplicationController
  include Hovercards::ConditionalAccessMethods

  before_action :require_xhr
  before_action :require_this_profile_highlight
  before_action :require_this_user

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    render "hovercards/profile_highlights/show", locals: {
      user: this_user,
      contribution_count: contribution_count,
      top_repositories: top_repositories,
      profile_highlight_type: this_profile_highlight.highlight_type
    }, layout: false
  end

  private

  def contribution_count
    this_profile_highlight.contribution_count
  end

  def top_repositories
    this_profile_highlight.top_repositories
  end

  def require_this_profile_highlight
    return render_404 if this_profile_highlight.nil?
    return render_404 unless this_profile_highlight.displayable?
  end

  def require_this_user
    render_404 unless this_user
  end

  def this_profile_highlight
    this_user.profile_highlights.find_by_highlight_type(params[:highlight_type])
  end

  memoize def this_user
    User.find_by(type: "User", login: params[:user_id])
  end

  def target_for_conditional_access
    this_user
  end
end
