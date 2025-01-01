# typed: strict
# frozen_string_literal: true

module Discussions
  class Comments::DeleteContentModalsController < Discussions::BaseController
    extend T::Sig

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      only: [:show]

    before_action :login_required
    before_action :require_discussion
    before_action :require_discussion_comment
    before_action :can_delete_comment?

    sig { void }
    def show
      respond_to do |format|
        format.html do
          render Discussions::DeleteCommentFormComponent.new(
            comment: T.must(discussion_comment),
            timeline: discussion_timeline
          ), layout: false
        end
      end
    end

    private

    sig { returns(T.nilable(DiscussionComment)) }
    memoize def discussion_comment
      discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
      discussion.comments.find_by(id: params[:comment_id].to_i)
    end

    sig { void }
    def require_discussion_comment
      render_404 unless discussion_comment
    end

    sig { void }
    def can_delete_comment?
      render_404 unless discussion_timeline.can_delete?(discussion_comment)
    end
  end
end
