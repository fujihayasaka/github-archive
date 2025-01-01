# typed: false
# frozen_string_literal: true

module Configurable
  module RestrictNonCommentPullRequestReviews
    extend Configurable::Async

    KEY = "restrict_non_comment_pull_request_reviews"
    VALUE_NO_RESTRICTION = "no_restriction"
    VALUE_REPO_ACCESS = "repo_access"

    def non_comment_pull_request_reviews_restricted?
      config.get(KEY) == VALUE_REPO_ACCESS
    end

    def restrict_non_comment_pull_request_reviews(actor:, override: false)
      config.set!(KEY, VALUE_REPO_ACCESS, actor, override)
    end

    def unrestrict_non_comment_pull_request_reviews(actor:, override: false)
      config.set!(KEY, VALUE_NO_RESTRICTION, actor, override)
    end

    def unset_non_comment_pull_request_reviews(actor:)
      if non_comment_pull_request_reviews_source == self
        config.delete(KEY, actor)
      else
        false
      end
    end

    def non_comment_pull_request_reviews_source
      config.source(KEY)
    end
  end
end
