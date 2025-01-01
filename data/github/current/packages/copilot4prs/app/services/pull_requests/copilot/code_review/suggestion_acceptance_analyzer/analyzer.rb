# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::SuggestionAcceptanceAnalyzer
  class Analyzer
    include GitHub::Memoizer

    def initialize(pull_request:)
      @pull_request = pull_request
    end

    sig { void }
    def analyze
      return if pull_request.nil?
      # TODO: figure out if this is the best way to query for copilot comments
      # and determine if we need an index on the review variant
      # the other option is to query for the integration's bot as the author
      copilot_comments = pull_request.review_comments.authored_by_copilot
      return if copilot_comments.empty?

      comments_with_suggestions = copilot_comments.select { |comment| comment.body_may_contain_suggestion? }
      possibly_accepted_comments = comments_with_suggestions.select(&:outdated?)
      return if possibly_accepted_comments.empty?

      possibly_accepted_comments.each do |comment|
        # Extract the suggestion from the comment body
        match = comment.body.match(/```suggestion\n(.*?)```/m)
        next unless match
        match_found = true

        suggestion_content = match[1].rstrip

        payload = {
          request_id: GitHub.context[:request_id],
          organization_id: pull_request.owner&.id,
          repository_id: pull_request.repository.id,
          pull_request_id: pull_request.id,
          comment_id: comment.id.to_s,
          analytics_tracking_id: pull_request.user.analytics_tracking_id,
        }

        # Check if the suggestion is present in the pull request diff
        diff_entry = pull_request_diff.with_path(comment.path)
        if diff_entry && diff_entry.text.include?(suggestion_content) && !comment.left_blob
          payload[:fully_applied] = true
        else
          # perform algorithm checks for partial acceptance
          # TODO: work in Needleman
          payload[:levenshtein_distance] = GitHub::Levenshtein.similarity(diff_entry.b_blob, suggestion_content)
        end
        GlobalInstrumenter.instrument("copilot.reviews.v0.SuggestionAnalysis", payload)
      end
    end

    private

    memoize def pull_request_diff
      pull_request.diffs
    end

    attr_reader :pull_request
  end
end
