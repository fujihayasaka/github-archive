# typed: true
# frozen_string_literal: true

# Emoji-ish reactions that can be attached to IssueComments.
class IssueCommentReaction < ApplicationRecord::Domain::IssuesPullRequests
  include Reaction::Common
end
