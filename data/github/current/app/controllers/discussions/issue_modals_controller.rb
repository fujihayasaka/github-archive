# typed: true
# frozen_string_literal: true

class Discussions::IssueModalsController < Discussions::BaseController
  before_action :require_discussion
  before_action :login_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  def show
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    respond_to do |format|
      format.html do
        render Discussions::IssueModalComponent.new(
          discussion_or_comment: discussion,
          repository: current_repository,
        ), layout: false
      end
    end
  end
end
