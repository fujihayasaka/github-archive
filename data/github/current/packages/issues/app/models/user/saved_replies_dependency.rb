# typed: true
# frozen_string_literal: true

module User::SavedRepliesDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))
    has_many :saved_replies
  end

  DEFAULT_SAVED_REPLY_TEMPLATES = {
    issue: [
      {
        title: "Duplicate issue",
        body: "Duplicate of #",
      },
    ],
    pull_request: [
      {
        title: "Fixes issue",
        body: "Fixes #",
      },
    ],
    pull_request_comment: [
      {
        title: "Duplicate pull request",
        body: "Duplicate of #",
      },
    ],
    new_pull_request: [
      {
        title: "Fixes issue",
        body: "Fixes #",
      },
    ],
  }.freeze

  # Public: Returns a list of this user's personal saved replies as well as general-purpose
  # shared replies.
  #
  # context - an optional context for the saved reply, to include only those replies that make
  #           sense on a particular page
  #
  # Returns a list of persisted and unpersisted SavedReply instances.
  def available_saved_replies(context: nil)
    all_saved_replies = default_saved_replies(context: context) + saved_replies.order(:title)
    all_saved_replies.sort_by { |reply| reply.title.downcase }
  end

  private

  # Private: Returns a list of unpersisted SavedReplies for this user, based on the default
  # templates.
  #
  # context - an optional context for the saved reply, to include only those replies that make
  #           sense on a particular page
  #
  # Returns a list of unpersisted SavedReply instances.
  def default_saved_replies(context: nil)
    templates = if context
      DEFAULT_SAVED_REPLY_TEMPLATES[context] || []
    else
      DEFAULT_SAVED_REPLY_TEMPLATES.values.flatten
    end

    templates.map do |template|
      saved_replies.build(template)
    end
  end
end
