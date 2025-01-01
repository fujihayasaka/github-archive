# typed: strict
# frozen_string_literal: true

module Discussions
  class Comments::UnminimizeContentModalsController < Discussions::BaseController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::NotificationsEntries,
      only: [:show]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show],
      optional: true

    before_action :login_required
    before_action :require_discussion
    before_action :require_discussion_comment
    before_action :require_minimize_state_is_toggleable

    sig { void }
    def show
      respond_to do |format|
        format.html do
          render Discussions::UnminimizeCommentModalFormComponent.new(
            comment: T.must(discussion_comment),
            timeline: discussion_timeline
          ), layout: false
        end
      end
    end

    private

    sig { returns(T.nilable(DiscussionComment)) }
    memoize def discussion_comment
      discussion = self.discussion
      return unless discussion
      discussion.comments.find_by(id: params[:comment_id].to_i)
    end

    sig { void }
    def require_discussion_comment
      render_404 unless discussion_comment
    end

    sig { void }
    def require_minimize_state_is_toggleable
      render_404 unless discussion_timeline.can_toggle_minimize?
    end
  end
end
