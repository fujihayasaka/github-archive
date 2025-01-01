# typed: true
# frozen_string_literal: true

module Discussions
  class PermissionsController < Discussions::BaseController # rubocop:todo GitHub/ControllersShouldHaveTests
    before_action :require_discussion

    def show
      render json: { "discussion" => permissions }
    end

    private

    def permissions
      discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
      { update: discussion.modifiable_by?(current_user) }
    end
  end
end
