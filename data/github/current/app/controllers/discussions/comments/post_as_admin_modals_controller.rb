# typed: strict
# frozen_string_literal: true

module Discussions
  class Comments::PostAsAdminModalsController < Discussions::BaseController
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
    before_action :require_user_can_post_as_admin
    before_action :require_author_is_admin

    sig { void }
    def show
      respond_to do |format|
        format.html do
          render Discussions::PostAsAdminModalFormComponent.new(
            discussion_or_comment: T.must(discussion_or_comment),
            timeline: discussion_timeline
          ), layout: false
        end
      end
    end

    private

    sig { void }
    def require_discussion_comment
      render_404 unless discussion_or_comment
    end

    sig { returns(T.nilable(T.any(Discussion, DiscussionComment))) }
    memoize def discussion_or_comment
      if params[:comment_id].present?
        discussion&.comments&.find_by(id: params[:comment_id])
      else
        # For discussions, we can directly use the discussion from the base controller
        # which properly retrieves it using the discussion_number or number parameter
        discussion
      end
    end

    sig { void }
    def require_user_can_post_as_admin
      render_404 unless can_post_as_admin?
    end

    sig { void }
    def require_author_is_admin
      render_404 unless discussion_or_comment&.author&.site_admin? || discussion_or_comment&.author&.employee?
    end
  end
end
