# typed: true
# frozen_string_literal: true

module Discussions
  class Comments::ThreadsController < Discussions::BaseController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql5,
      only: [:show]

    NUMBER_OF_NESTED_COMMENTS_PER_PAGE = 50

    before_action :require_discussion
    before_action :require_comment

    def show
      preload_discussion_timeline

      render(
        Discussions::ChildCommentsComponent.new(
          parent_comment: comment,
          page: page + 1,
          timeline: discussion_timeline,
          back_page: back_page,
          forward_page: forward_page,
          anchor_id: anchor_id,
        ),
        layout: false,
      )
    end

    private

    def discussion_timeline_render_context
      DiscussionTimeline::SingleCommentRenderContext.new(
        discussion,
        comment,
        viewer: current_user,
        cap_filter: cap_filter,
        nested_comments_page: page,
        nested_comments_per_page: NUMBER_OF_NESTED_COMMENTS_PER_PAGE,
        anchor_id: anchor_id,
        back_page: back_page,
        forward_page: forward_page,
      )
    end

    def preload_discussion_timeline
      discussion_timeline.preload_comments
      DiscussionTimeline::PermissionPreloader.load_for(
        discussion_timeline,
        can_interact_with_repo: can_interact_with_repo?
      )
      discussion_timeline.preload_author_roles
      discussion_timeline.preload_body_html
    end

    def page
      param_to_i(:page, 1)
    end

    def back_page
      param_to_i(:back_page, 0)
    end

    def forward_page
      param_to_i(:forward_page, 0)
    end

    def anchor_id
      param_to_i(:anchor_id, 0)
    end

    def param_to_i(param, default_id_or_page)
      if params[param].blank? || !params[param].respond_to?(:to_i)
        default_id_or_page
      else
        params[param].to_i.abs
      end
    end
  end
end
