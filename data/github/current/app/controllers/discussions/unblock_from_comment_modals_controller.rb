# typed: strict
# frozen_string_literal: true

module Discussions
  class UnblockFromCommentModalsController < Discussions::BaseController
    before_action :require_discussion
    before_action :require_org_discussion
    before_action :require_comment_if_specified
    before_action :login_required

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Spokes,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Billing,
      only: [:show]

    sig { void }
    def show
      discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
      current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
      respond_to do |format|
        format.html do
          render Discussions::UnblockUserFromCommentFormComponent.new(
            discussion_or_comment: discussion_comment || discussion,
            repository: current_repository,
          ), layout: false
        end
      end
    end

    private

    sig { void }
    def require_org_discussion
      render_404 unless discussion&.in_organization?
    end

    sig { returns(T.nilable(DiscussionComment)) }
    memoize def discussion_comment
      discussion = self.discussion
      return unless discussion
      discussion.comments.find_by(id: params[:comment_id]) if params[:comment_id].present?
    end

    sig { void }
    def require_comment_if_specified
      render_404 if params[:comment_id].present? && discussion_comment.nil?
    end
  end
end
