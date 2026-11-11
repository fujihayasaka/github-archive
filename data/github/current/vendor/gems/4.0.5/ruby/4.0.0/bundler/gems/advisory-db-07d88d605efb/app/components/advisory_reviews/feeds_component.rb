# frozen_string_literal: true

module AdvisoryReviews
  class FeedsComponent < ApplicationComponent
    attr_reader :advisory_review

    delegate :advisory, to: :advisory_review

    def initialize(advisory_review:)
      @advisory_review = advisory_review
    end

    def render?
      !advisory_review.read_only? && feed_entries.any?
    end

    def feed_entries
      return @feed_entries if defined? @feed_entries

      @feed_entries = advisory_review.feed_entries.order(updated_at: :desc)
    end

    def feed_entries_since_publish
      return @feed_entries_since_publish if defined? @feed_entries_since_publish

      @feed_entries_since_publish = feed_entries
      if advisory
        @feed_entries_since_publish = feed_entries.select { |feed_entry| feed_entry.updated_at > advisory.updated_at }
      end

      @feed_entries_since_publish
    end
  end
end
