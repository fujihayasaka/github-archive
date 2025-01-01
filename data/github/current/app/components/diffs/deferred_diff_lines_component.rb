# typed: true
# frozen_string_literal: true

module Diffs
  class DeferredDiffLinesComponent < GitHub::BatchDeferredContentComponent
    TAG_NAME = "deferred-diff-lines"
    DEFAULT_CLASSES = ["awaiting-highlight"].freeze

    module HighlightingModes
      DEFERRED = :deferred
      IMMEDIATE = :immediate
    end

    attr_reader :context_lines, :highlighting_mode

    def initialize(context_lines: nil, highlighting_mode: nil, **kwargs)
      @context_lines = context_lines
      @highlighting_mode = highlighting_mode

      super(**T.unsafe(kwargs))
    end

    def content_tag_name
      TAG_NAME
    end

    def classes
      Array.wrap(super) + DEFAULT_CLASSES
    end

    def did_defer_syntax_highlighting?
      (highlighting_mode.nil? || highlighting_mode == HighlightingModes::DEFERRED) &&
        @url.present?
    end
  end
end
