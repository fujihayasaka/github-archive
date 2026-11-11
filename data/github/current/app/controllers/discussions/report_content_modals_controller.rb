# typed: strict
# frozen_string_literal: true

module Discussions
  class ReportContentModalsController < Discussions::BaseController
    before_action :require_discussion
    before_action :require_discussion_in_organization
    before_action :require_tiered_reporting_enabled
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
          render Discussions::ReportContentFormComponent.new(
            discussion_or_comment: discussion_comment || discussion,
            repository: current_repository,
            timeline: discussion_timeline,
            org_param: org_param,
          ), layout: false
        end
      end
    end

    private

    sig { void }
    def require_discussion_in_organization
      render_404 unless discussion&.in_organization?
    end

    sig { void }
    def require_tiered_reporting_enabled
      tiered_reporting_enabled = current_repository&.tiered_reporting_explicitly_enabled?
      tiered_reporting_all_users_enabled = current_repository&.tiered_reporting_all_users_explicitly_enabled?

      render_404 if !tiered_reporting_enabled && !tiered_reporting_all_users_enabled
    end

    sig { returns(T.nilable(DiscussionComment)) }
    memoize def discussion_comment
      discussion&.comments&.find_by(id: params[:comment_id]) if params[:comment_id].present?
    end

    sig { void }
    def require_comment_if_specified
      render_404 if params[:comment_id].present? && discussion_comment.nil?
    end
  end
end
