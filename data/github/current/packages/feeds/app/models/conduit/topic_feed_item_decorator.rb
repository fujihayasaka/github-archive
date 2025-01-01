# typed: true
# frozen_string_literal: true

module Conduit
  class TopicFeedItemDecorator
    extend T::Sig

    sig { params(items: T::Array[Conduit::FeedItem], buckets: T::Hash[String, Symbol]).void }
    def self.apply_bucket_labels(items, buckets)
      items.each do |item|
        keys = T.let([], T::Array[String]).tap do |a|
          a << "repo:#{item.repository.id}" if item.repository
          a << "user:#{item.actor.id}" if item.actor
        end

        next unless key = keys.find { |key| buckets.key?(key) }

        label = buckets[key]
        label = label.to_s.capitalize.sub("_", " ")
        item.apply_label(label)
      end

      nil
    end
  end
end
