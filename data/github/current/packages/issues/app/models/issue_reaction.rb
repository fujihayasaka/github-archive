# typed: true
# frozen_string_literal: true

# Emoji-ish reactions that can be attached to Issues.
class IssueReaction < ApplicationRecord::Domain::IssuesPullRequests
  include Reaction::Common
end
