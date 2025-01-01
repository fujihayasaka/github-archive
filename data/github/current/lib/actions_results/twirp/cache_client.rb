# typed: strict
# frozen_string_literal: true

require "monolith-twirp-actionsresults-core"

module ActionsResults
  module Twirp
    class CacheClient < ActionsResults::Twirp::BaseClient
      Direction = MonolithTwirp::ActionsResults::Core::V1::ListCachesRequest::Direction
      Sort = MonolithTwirp::ActionsResults::Core::V1::ListCachesRequest::Sort

      sig do
        params(
          repository_id: Integer,
          key: T.nilable(String),
          scope: T.nilable(String),
          sort: T.nilable(String),
          direction: T.nilable(String),
          page: Integer,
          per_page: Integer,
        ).returns(TwirpResponse)
      end
      def list_caches(repository_id:, key: nil, scope: nil, sort: nil, direction: nil, page: 1, per_page: 30)
        rpc(
          :ListCaches,
          repository_id:,
          key:,
          scope:,
          sort: self.class.to_sort(sort),
          direction: self.class.to_direction(direction),
          page:,
          per_page:,
        )
      end

      sig do
        params(
          repository_id: Integer,
          cache_id: Integer,
        ).returns(TwirpResponse)
      end
      def delete_cache_by_id(repository_id:, cache_id:)
        rpc(
          :DeleteCacheByID,
          repository_id:,
          cache_id:,
        )
      end

      sig do
        params(
          repository_id: Integer,
          key: String,
          scope: T.nilable(String)
        ).returns(TwirpResponse)
      end
      def delete_caches_by_key(repository_id:, key:, scope:)
        rpc(
          :DeleteCachesByKey,
          repository_id:,
          key:,
          scope:,
        )
      end

      sig { params(direction: T.nilable(String)).returns(Integer) }
      def self.to_direction(direction)
        case direction&.downcase
        when "desc"
          Direction::DIRECTION_DESC
        when "asc"
          Direction::DIRECTION_ASC
        else
          Direction::DIRECTION_DESC
        end
      end

      sig { params(sort: T.nilable(String)).returns(Integer) }
      def self.to_sort(sort)
        case sort&.downcase
        when "created_at"
          Sort::SORT_CREATED_AT
        when "last_accessed_at"
          Sort::SORT_LAST_ACCESSED_AT
        when "size_in_bytes"
          Sort::SORT_SIZE_IN_BYTES
        else
          Sort::SORT_LAST_ACCESSED_AT
        end
      end

      private

      sig { returns(T.class_of(::Twirp::Client)) }
      def twirp_class
        ::MonolithTwirp::ActionsResults::Core::V1::CacheServiceAPIClient
      end
    end
  end
end
