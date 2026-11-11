# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  class GetIssueSkillResponse
    include GitHub::Memoizer
    include Copilot::Prompt::Tokens

    # We have about 4_000 tokens to work with but we also need to factor in the JSON keys. So we deduct some
    # tokens to account for that. We also want some buffer for followup questions.
    MAX_TOKENS = 2_000
    MAX_ISSUE_COMMENTS = 40
    TOO_MANY_COMMENTS_MESSAGE = <<-TEXT.squish
      There are too many comments so you must let the user know the results are
      incomplete by putting this message only at the very end of the response:
      'Some of the issue's comments could not be read because the issue body and
      comments combined are too long.'
    TEXT
    ISSUE_BODY_TOO_LARGE = <<-TEXT.squish
      The issue is too big so only part of the body was included and no comments
      are available. You must let the user know the results are incomplete by
      putting this message only at the very end of the response: 'Part of the
      issue's body could not be read and no comments were read because the issue
      body is too long.'
    TEXT

    sig { params(issue: ::Issue, current_user: ::User).void }
    def initialize(issue:, current_user:)
      @issue = issue
      @current_user = current_user
    end

    def payload
      {
        issue: {
          number: issue.number,
          title: issue.title,
          body: issue_body_and_comments.to_s,
          user: {
            login: issue.user&.display_login
          },
          state: issue_state,
          pull_request: {
            html_url: issue.pull_request&.url
          },
          id: issue.id,
          repo_id: issue.repository_id,
          assignees: issue.assignees.map(&:display_login),
          url: issue.permalink,
          created_at: Google::Protobuf::Timestamp.new(seconds: issue.created_at.to_i),
          updated_at: Google::Protobuf::Timestamp.new(seconds: issue.updated_at.to_i),
          closed_at: issue.closed_at.nil? ? nil : Google::Protobuf::Timestamp.new(seconds: issue.closed_at.to_i),
        }
      }
    end

    private

    sig { returns(Issue) }
    attr_reader :issue
    sig { returns(::User) }
    attr_reader :current_user

    # Because every PR as an associated issue, we can ask about a PR as an issue.
    # However, the state of the issue is limited to open or closed,
    # which is not reflective of the actual PR state,
    # so we return the PR state instead if the issue is linked to a PR.
    sig { returns(T.nilable(String)) }
    def issue_state
      # if user is asking about an issue
      return issue.state unless issue.pull_request?
      # else we assume that the user is asking about a pull request
      pull_request = T.must(issue.pull_request)

      pull_request.draft? && pull_request.open? ? "draft" : pull_request.state.to_s
    end

    # Returns a Hash that will be used as a string that the model can use to get the issue body and comments
    # The model doesn't really care that the Hash is stringified since to the model it appears in the same way.
    #
    # This makes it so that we can quickly iterate on comments until we have a better idea of how we'd like to use
    # it. For example, we may want a separate skill, or we may want to add a new field to the existing get_issue
    # Twirp endpoint.
    #
    # See: https://github.com/github/copilot-core-productivity/issues/1529
    sig { returns(T::Hash[Symbol, T.any(String, T::Array[T::Hash[Symbol, String]])]) }
    def issue_body_and_comments
      payload = {
        # Only get the body up until the token limit
        body: (issue.body || "").first(MAX_TOKENS * Copilot::Prompt::Tokens::CHARACTERS_PER_TOKEN),
        # Reverse comments to put the oldest comment first which makes more sense
        # when summarizing issues and gets better results from the model.
        comments: issue_comments_hash.reverse
      }

      if issue_body_token_count > MAX_TOKENS
        # If the body is too big then no comments will be included. Let the user know
        payload.merge(ai_notes: ISSUE_BODY_TOO_LARGE)
      elsif issue_comments_hash.count < issue_comments.count
        # If some comments were removed then let's let the user know
        payload.merge(ai_notes: TOO_MANY_COMMENTS_MESSAGE)
      else
        # Otherwise don't return any notes about truncation
        payload
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    memoize def issue_comments_hash
      # Start with the issue body token count. That way if the body is huge we only add a few comments. If the body
      # is small we can add more comments.
      total_content_token_count = issue_body_token_count

      issue_comments.take_while do |comment|
        total_content_token_count += count_tokens(comment.body)
        # If adding this comment would put us over the limit, break out of
        # the loop and skip the rest of the comments.
        total_content_token_count < MAX_TOKENS
      end.map do |comment|
        {
          body: comment.body,
          author: comment.user&.display_login,
          created_at: comment.created_at
        }
      end
    end

    sig { returns(Integer) }
    memoize def issue_body_token_count
      return 0 if issue.body.nil?
      count_tokens(issue.body)
    end

    memoize def issue_comments
      IssueComment
        .where(issue: issue)
        .includes(:user)
        # Get rid of the noise
        .where(comment_hidden: false, performed_by_integration_id: nil)
        .filter_spam_for(current_user)
        # Sort to get the newest comments first since those are likely the most interesting ones to summarize. Then
        .sorted_by(:created_at, :desc)
        # Limit them so we don't overwhelm the database.
        .limit(MAX_ISSUE_COMMENTS)
    end
  end
end
