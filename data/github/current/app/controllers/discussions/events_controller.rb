# typed: true
# frozen_string_literal: true

module Discussions
  class EventsController < Discussions::BaseController
    before_action :require_discussion

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Mysql5,
      only: [:show]

    def show
      render(
        partial: "discussions/events_list",
        locals: { discussion: discussion, timeline: discussion_timeline, events: discussion_timeline.events },
        layout: false
      )
    end

    private

    def discussion_timeline_render_context
      discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
      DiscussionTimeline::PaginatedRenderContext.new(
        discussion,
        viewer: current_user,
        paginate_events: false
      )
    end
  end
end
