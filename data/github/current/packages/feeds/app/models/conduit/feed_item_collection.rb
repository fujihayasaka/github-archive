# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItemCollection < Array
    # This should ultimately happen in Conduit by excluding
    # items in the gather step. This would ensure a full feed,
    # even with many filteres enabled.
    # See https://github.com/github/feeds/discussions/1268
    def apply_filter(filter)
      return FeedItemCollection.new(self) unless filter.present?

      select! do |item|
        filter.include_item?(item)
      end

      FeedItemCollection.new(self)
    end

    def filter_feed_posts(viewer:)
      return self if GitHub.flipper[:feed_posts].enabled?(viewer)

      delete_if do |item|
        TwirpHelper.key_for_item(item) == TwirpHelper.created_feed_post_key
      end

      FeedItemCollection.new(self)
    end

    # This is here and not in Conduit because we want to randomize recs even if the
    # feed is cached.
    #
    # The algorithm is to isolate recs and their corresponding index
    # within the twirp_items list. Once isolated, shuffle the recs and
    # re-insert them.
    def shuffle_repo_recs
      recs = []
      rec_indexes = []

      each_with_index do |item, index|
        if TwirpHelper.key_for_item(item) == TwirpHelper.repository_recommendation_key
          recs << item
          rec_indexes << index
        end
      end

      recs.shuffle!

      rec_indexes.each_with_index do |index, i|
        self[index] = recs[i]
      end

      FeedItemCollection.new(self)
    end

    def filter_off_topic_repos(topic)
      return FeedItemCollection.new(self) if topic.nil?

      repo_ids = collect_repo_ids(self)

      allowed_repo_ids = RepositoryTopic
        .where(topic: topic, repository_id: repo_ids)
        .pluck(:repository_id)

      remove_off_topic_repos(self, allowed_repo_ids)

      FeedItemCollection.new(self)
    end

    def filter_trending_repos(viewer:)
      if viewer.in_onboarding_period? && viewer.feature_enabled?(:nux_explore_repos)
        delete_if { |item| TwirpHelper.key_for_item(item) == TwirpHelper.trending_repository_key }
      end

      FeedItemCollection.new(self)
    end

    private

    # Find all repository IDs. Recursively searches through
    # all related items
    def collect_repo_ids(items)
      items.filter_map do |item|
        next unless repo_id = repo_id_for(item)
        [repo_id] + collect_repo_ids(item.related_items)
      end.flatten
    end

    # Delete items if the subject is a repository but the repository is
    # not tagged with the topic
    def remove_off_topic_repos(items, allowed_repo_ids)
      items.delete_if do |item|
        next false unless repo_id = repo_id_for(item)
        remove_off_topic_repos(item.related_items, allowed_repo_ids)
        !allowed_repo_ids.include?(repo_id)
      end
    end

    def repo_id_for(item)
      case item.subject_type
      when TwirpHelper.repository_subject_type
        item.repository_subject&.id
      when TwirpHelper.user_list_item_subject_type
        item.user_list_item_subject.repository&.id
      when TwirpHelper.discussion_subject_type
        item.discussion_subject.repository&.id
      when TwirpHelper.pull_request_subject_type
        item.pull_request_subject.repository_id
      when TwirpHelper.release_subject_type
        item.release_subject.repository&.id
      end
    end
  end
end
