# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::Repository < FeedItem
    def repository
      subject
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

    def payload
      {}
    end
  end
end
