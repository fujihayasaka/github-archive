# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::TimelineEvents
  # Shared serializer that converts `TimelineEvents::Loader::Event` structs
  # into a stable wire-format payload used by the catch-up snapshot
  # (`PullRequests::PageData::CatchUpSnapshot::Payload`). The paginated PR
  # timeline renders the same loader output as proto via
  # `PullRequests::PageData::Timeline::ProtoPayload`, which mirrors this
  # serializer's per-field transforms onto the proto message.
  class Payload
    class UserPayload < T::Struct
      const :id, Integer
      const :displayLogin, String
      const :avatarUrl, String
    end

    class TimelineItemPayload < T::Struct
      const :id, String
      const :type, String
      const :timestamp, T.nilable(String)
      const :user, T.nilable(UserPayload)
      const :additionalInfo, T.nilable(T::Hash[Symbol, T.untyped])
    end

    sig { params(items: T::Array[PullRequests::PageData::TimelineEvents::Loader::Event]).returns(T::Array[TimelineItemPayload]) }
    def self.call(items)
      new.call(items)
    end

    sig { params(items: T::Array[PullRequests::PageData::TimelineEvents::Loader::Event]).returns(T::Array[TimelineItemPayload]) }
    def call(items)
      items.map { |item| serialize_item(item) }
    end

    private

    sig { params(item: PullRequests::PageData::TimelineEvents::Loader::Event).returns(TimelineItemPayload) }
    def serialize_item(item)
      user_payload = if (user = item.user)
        UserPayload.new(
          id: user.id,
          displayLogin: user.display_login,
          avatarUrl: user.avatar_url
        )
      end

      TimelineItemPayload.new(
        id: item.id,
        type: item.type,
        timestamp: item.timestamp&.iso8601,
        user: user_payload,
        additionalInfo: item.additional_info.empty? ? nil : item.additional_info
      )
    end
  end
end
