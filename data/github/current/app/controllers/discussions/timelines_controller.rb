# typed: true
# frozen_string_literal: true

class Discussions::TimelinesController < Discussions::BaseController
  before_action :require_discussion
  preload_features USER_CONTENT_FEATURES

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    respond_to do |format|
      format.html do
        render partial: "discussions/timeline", locals: {
          timeline: discussion_timeline,
          timeline_sort: timeline_sort,
          org_param: org_param,
        }
      end
    end
  end

  private

  def timeline_last_modified
    return nil if params[:timeline_last_modified].blank?

    Time.parse(params[:timeline_last_modified])
  rescue ArgumentError
    nil
  end

  def discussion_timeline_render_context
    DiscussionTimeline::LiveUpdatesRenderContext.new(
      discussion,
      viewer: current_user,
      timeline_last_rendered: timeline_last_modified,
      sort: timeline_sort,
      cap_filter: cap_filter
    )
  end
end
