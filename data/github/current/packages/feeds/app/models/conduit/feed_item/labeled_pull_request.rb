# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::LabeledPullRequest < FeedItem::PullRequest
    # display
    def action_string
      "labeled a pull request"
    end

    def description
      "#{actor} #{action_string} #{label.name} in #{repository.name}"
    end

    # analytics
    def analytics_card_type
      CardType::LABELED_PULL_REQUEST
    end

    def payload_action
      :labeled
    end

    def payload
      super.merge({
        label: labels.last,
        labels: labels
      })
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
      twirp_item.pull_request_subject.labels.map(&:id)
    end
  end
end
