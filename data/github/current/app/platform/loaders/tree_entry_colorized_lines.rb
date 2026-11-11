# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class TreeEntryColorizedLines < Platform::Loader
      DEFAULT_TIMEOUT = 1

      def self.load(tree_entry, timeout_counter: GitHub::TimeoutCounter.new(DEFAULT_TIMEOUT))
        if tree_entry.language && GitHub::Colorize.valid_scope?(tree_entry.language.tm_scope) && tree_entry.safe_to_colorize?
          self.for(timeout_counter).load(tree_entry)
        else
          Promise.resolve(nil)
        end
      end

      def initialize(timeout_counter)
        @timeout_counter = timeout_counter
      end

      def fetch(tree_entries)
        return {} if @timeout_counter.timeout?

        scopes = tree_entries.map { |tree_entry| tree_entry.language.tm_scope }
        contents = tree_entries.map { |tree_entry| tree_entry.data }

        highlighting_results = @timeout_counter.update do
          GitHub::Colorize.highlight_many(scopes, contents, timeout: @timeout_counter.remaining)
        end

        tree_entries.zip(highlighting_results).to_h
      end
    end
  end
end
