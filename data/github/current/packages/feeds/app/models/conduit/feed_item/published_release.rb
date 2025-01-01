# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PublishedRelease < FeedItem
    delegate :repository, :tag_name, to: :release

    GRAPHQL_TYPE = Platform::Objects::Conduit::PublishedReleaseFeedItem

    def release
      subject
    end

    # Display
    def action_string
      "published a release"
    end

    def description
      "#{actor} published a release"
    end

    # Analytics
    def analytics_card_type
      CardType::PUBLISHED_RELEASE
    end

    def resource_type
      ResourceType::REPOSITORY
    end

    def resource_id
      repository.id
    end

    def source
      repository.name_with_display_owner
    end

    def api_type
      "ReleaseEvent"
    end

    def payload
      {
        action: :published,
        release: ::Api::Serializer.serialize(:release_hash, release, { include_mentions: true }).merge({
          short_description_html: short_description_html_info[:html],
          is_short_description_html_truncated: short_description_html_info[:truncated?],
        })
      }
    end

    private

    memoize def short_description_html_info
      release.short_description_html_info
    end
  end
end
