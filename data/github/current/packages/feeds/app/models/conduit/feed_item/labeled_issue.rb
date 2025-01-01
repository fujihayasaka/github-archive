# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::LabeledIssue < FeedItem::Issue
    # Display
    def action_string
      "labeled an issue"
    end

    # Analytics
    def analytics_card_type
      CardType::LABELED_ISSUE
    end

    def payload
      super.merge(
        {
          label: labels.last,
          labels: labels
        }
      )
    end

    def payload_action
      :labeled
    end

    def description
      "#{actor} #{action_string} #{label&.name} in #{repository.name}"
    end

    private

    memoize def labels
      label_records.map do |label|
        ::Api::Serializer
          .serialize(:label_hash, label, repo: repository)
          .deep_symbolize_keys
      end
    end

    memoize def label_records
      return [] if label_ids.empty?
      return cached_labels if cached_labels.any?

      Label.where(id: label_ids)
    end

    memoize def cached_labels
      return [] unless feed

      cached_labels = feed.cached_records[:labels].select do |label|
        label_ids.include?(label.id)
      end
    end

    memoize def label_ids
      twirp_item.issue_subject.labels.map(&:id)
    end
  end
end
