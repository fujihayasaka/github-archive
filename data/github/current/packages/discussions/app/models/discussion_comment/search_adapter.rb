# typed: true
# frozen_string_literal: true

module DiscussionComment::SearchAdapter
  extend T::Helpers

  requires_ancestor { DiscussionComment }

  sig { void }
  def synchronize_search_index
    discussion&.synchronize_search_index
  end
end
