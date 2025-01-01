# typed: strict
# frozen_string_literal: true

module Discussions
  class SaveAsDraftModalComponent < ApplicationComponent
    sig { returns(Discussion) }
    attr_reader :discussion

    sig { params(discussion: Discussion).void }
    def initialize(discussion:)
      @discussion = discussion
    end

    sig { returns(T::Boolean) }
    def render?
      discussion.scheduled?
    end

    sig { returns(String) }
    memoize def dialog_dom_id
      "dialog-save-draft-discussion-#{discussion.id}"
    end
  end
end
