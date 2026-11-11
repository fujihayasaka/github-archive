# typed: true
# frozen_string_literal: true

module Discussions
  class Comments::LanguageDetectionsController < Discussions::BaseController
    include ApplicationController::VerifiedFetchDependency

    before_action :login_required
    before_action :require_discussion, :require_comment

    allow_verified_fetch

    def create
      comment = T.must_because(self.comment) { "#require_comment ensures non-nil" }

      # Language detection runs when the comment gets updated, so only need this for old comments without a language.
      return head(:no_content) if comment.detected_language.present?

      if stale_model?(comment)
        discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
        return render_stale_error(model: comment,
          error: "Could not edit comment. Please try again.", path: agnostic_discussion_path(discussion, org_param: org_param))
      end

      comment.detect_comment_language

      head :accepted

    end
  end
end
