# typed: true
# frozen_string_literal: true

class Discussions::LanguageDetectionsController < Discussions::BaseController
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :require_discussion
  allow_verified_fetch

  def create
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }

    # Language detection runs when the discussion gets updated, so only need this for old discussions without a language.
    return head(:no_content) if discussion.detected_language.present?

    if stale_model?(discussion)
      return render_stale_error(model: discussion,
        error: "Could not edit discussion. Please try again.", path: agnostic_discussion_path(discussion, org_param: org_param))
    end

    discussion.detect_comment_language

    head :accepted
  end
end
