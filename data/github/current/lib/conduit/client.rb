# typed: true
# frozen_string_literal: true

require "faraday"
require "monolith-twirp-conduit-feeds"

module Conduit
  class Client
    SERVICE_NAME = "conduit_github_client"
    class Error < StandardError; end
    class PermissionDenied < Error; end
    class Unavailable < Error; end
    class Internal < Error; end

    def initialize(http_adapter: self.class.default_http_adapter)
      @http_adapter = http_adapter
      @twirp_client = MonolithTwirp::Conduit::Feeds::V1::GetFeedAPIClient.new(http_adapter)
    end

    def get_for_you_feed(user:, variants:, disable_cache: false, include_starred_relationships: true, repository_subscriptions: [], event_types: [])
      request = proc do
        response = twirp_client.get_feed(
          user_id: user.id,
          variant: variants.transform_values(&:to_s).to_json,
          include_starred_relationships: include_starred_relationships,
          subscriptions: repository_subscriptions,
          event_types: event_types,
        )

        if response.error
          handle_error(response.error)
        end

        GitHub.dogstats.distribution(
          "conduit.feed.bytesize", response.body.bytesize
        )

        response.body
      end

      body = if disable_cache
        request.call
      else
        Conduit::KVBackedCache.get_or_set_for(user) do
          request.call
        end
      end

      decoded_body = MonolithTwirp::Conduit::Feeds::V1::GetFeedResponse.decode(body)

      feed_items(decoded_body)
    end

    def get_org_feed(viewer:, org_id:)
      request = proc do
        response = twirp_client.get_org_feed(
          viewer_id: viewer.id,
          org_id: org_id,
        )

        if response.error
          handle_error(response.error)
        end

        response.body
      end

      cache_key = "org_feed.#{org_id}"
      body = cached_request(request, viewer, cache_key:)
      decoded_body = MonolithTwirp::Conduit::Feeds::V1::GetOrgFeedResponse.decode(body)

      unranked_feed_items(decoded_body)
    end

    def get_user_events(viewer:, user:, public_only: false)
      request = proc do
        response = twirp_client.get_user_events(
          viewer_id: viewer ? viewer.id : 0,
          user_id: user.id,
          is_public_only: public_only,
        )

        if response.error
          handle_error(response.error)
        end

        response.body
      end

      cache_key = "user_events.#{user.id}"
      cache_key += ".public_only" if public_only
      body = cached_request(request, viewer, cache_key:)
      decoded_body = MonolithTwirp::Conduit::Feeds::V1::GetUserEventsResponse.decode(body)

      unranked_feed_items(decoded_body)
    end

    def get_organization_events(viewer:, organization:, public_only: false)
      request = proc do
        response = twirp_client.get_organization_events(
          viewer_id: viewer ? viewer.id : 0,
          org_id: organization.id,
          is_public_only: public_only,
        )

        if response.error
          handle_error(response.error)
        end

        response.body
      end

      cache_key = "organization_events.#{organization.id}"
      cache_key += ".public_only" if public_only
      body = cached_request(request, viewer, cache_key:)
      decoded_body = MonolithTwirp::Conduit::Feeds::V1::GetOrganizationEventsResponse.decode(body)

      unranked_feed_items(decoded_body)
    end

    def get_user_received_events(viewer:, user:, public_only: false, repository_subscriptions: [])
      request = proc do
        response = twirp_client.get_user_received_events(
          viewer_id: viewer ? viewer.id : 0,
          user_id: user.id,
          is_public_only: public_only,
          subscriptions: repository_subscriptions
        )

        if response.error
          handle_error(response.error)
        end

        response.body
      end

      cache_key = "user_received_events.#{user.id}"
      cache_key += ".public_only" if public_only
      body = cached_request(request, viewer, cache_key:)
      decoded_body = MonolithTwirp::Conduit::Feeds::V1::GetUserReceivedEventsResponse.decode(body)

      unranked_feed_items(decoded_body)
    end

    def get_public_events(viewer:)
      request = proc do
        response = twirp_client.get_public_events(
          viewer_id: viewer ? viewer.id : 0,
        )

        if response.error
          handle_error(response.error)
        end

        response.body
      end

      cache_key = "public_events"
      body = cached_request(request, viewer, cache_key:)
      decoded_body = MonolithTwirp::Conduit::Feeds::V1::GetPublicEventsResponse.decode(body)

      unranked_feed_items(decoded_body)
    end

    def get_user_wiki_edits(viewer:, user:)
      request = proc do
        response = twirp_client.get_user_wiki_edits(
          viewer_id: viewer.id,
          user_id: user.id,
        )

        if response.error
          handle_error(response.error)
        end

        response.body
      end

      cache_key = "user_wiki_edits.#{user.id}"
      body = cached_request(request, viewer, cache_key:)
      decoded_body = MonolithTwirp::Conduit::Feeds::V1::GetUserWikiEditsResponse.decode(body)

      unranked_feed_items(decoded_body)
    end

    def delete_resource_events(resource_type:, resource_id:, is_public_only: false)
      response = twirp_client.delete_resource_events(
        resource_type:,
        resource_id:,
        is_public_only:,
      )

      if response.error
        handle_error(response.error)
      end
    end

    def unranked_feed_items(body)
      {
        items: ::Conduit::FeedItemCollection.new(body.feed_items)
      }
    end

    def feed_items(body)
      {
        items: ::Conduit::FeedItemCollection.new(body.feed_items),
        ranking_model_id: body.ranking_model_id,
      }
    end

    def get_topic_feed(viewer:, list:, topic_id:)
      response = twirp_client.get_list_feed(
        viewer_id: viewer.id,
        list: list,
        topic_id: topic_id,
      )

      if response.error
        handle_error(response.error)
      end

      feed_items(response.data)
    end

    def get_repository_events(viewer:, repository_ids:, issues_only: false)
      response = twirp_client.get_repository_events(
        viewer_id: viewer ? viewer.id : 0,
        repository_ids: repository_ids.join(","),
        issues_only:,
      )

      if response.error
        handle_error(response.error)
      end

      unranked_feed_items(response.data)
    end

    def create_feed_post_event(feed_post:)
      response = twirp_client.create_feed_post_event(feed_post: feed_post.to_twirp)
      raise Error.new(response.error.msg) if response.error
    end

    def delete_feed_post_event(feed_post_id:)
      response = twirp_client.delete_feed_post_event(feed_post_id: feed_post_id)
      raise Error.new(response.error.msg) if response.error
    end

    def self.default_http_adapter
      GitHub::FaradayClient::Internal.new(url: GitHub.conduit_twirp_url) do |c|
        c.headers[:user_agent] = "github-#{GitHub.role}"
        c.options[:timeout] = 10
        c.request(:retry, max: 2)
        c.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.conduit_hmac_key
        c.use GitHub::FaradayMiddleware::RequestID
        c.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
        c.adapter(:typhoeus)
      end
    end

    def handle_error(error)
      case error.code
      when :permission_denied
        raise PermissionDenied, error.msg
      when :unavailable
        raise Unavailable, error.msg
      when :internal
        raise Internal, error.msg
      else
        raise Error, error.msg
      end
    end

    def cached_request(request, viewer, cache_key: nil)
      body = if GitHub.flipper[:feeds_conduit_cache_opt_out].enabled?(viewer) || viewer.nil?
        request.call
      else
        Conduit::KVBackedCache.get_or_set_for(viewer, cache_key:) do
          request.call
        end
      end
    end

    attr_reader :http_adapter, :twirp_client
  end
end
