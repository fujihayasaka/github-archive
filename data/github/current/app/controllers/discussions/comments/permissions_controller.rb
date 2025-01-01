# typed: true
# frozen_string_literal: true

module Discussions
  module Comments
    class PermissionsController < Discussions::BaseController # rubocop:todo GitHub/ControllersShouldHaveTests
      before_action :require_discussion
      before_action :require_comment

      def show
        render json: { "comment" => permissions }
      end

      private

      def permissions
        comment = T.must_because(self.comment) { "#require_comment ensures non-nil" }
        { update: comment.modifiable_by?(current_user) }
      end
    end
  end
end
