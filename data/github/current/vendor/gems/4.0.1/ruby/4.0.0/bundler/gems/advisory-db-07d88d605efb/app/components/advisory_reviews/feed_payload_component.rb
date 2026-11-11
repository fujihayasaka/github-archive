# frozen_string_literal: true

module AdvisoryReviews
  class FeedPayloadComponent < ApplicationComponent
    attr_reader :feed_entry

    def initialize(feed_entry:)
      @feed_entry = feed_entry
    end

    def header
      feed_entry.identifier
    end

    def header_link
      return unless feed_entry.raw_payload["pr_number"]

      "https://github.com/#{AdvisoryDB.github_advisories_repo}/pull/#{feed_entry.raw_payload["pr_number"]}"
    end

    def payload_diff
      existing_advisory_payload = NormalYAML.dump({ advisory_payload: feed_entry.advisory_review.advisory_payload })
      feed_advisory_payload = NormalYAML.dump({ advisory_payload: feed_entry.advisory_payload })

      # Add raw payload to both sides so it doesn't get diff visuals
      raw_payload = "\n\n#{NormalYAML.dump({ raw_payload: feed_entry.raw_payload })}"
      left = existing_advisory_payload + raw_payload
      right = feed_advisory_payload + raw_payload

      Diffy::Diff.new(left, right).to_s.html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end
