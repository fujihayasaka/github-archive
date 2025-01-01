# typed: true
# frozen_string_literal: true

module Conduit
  autoload :Client, "conduit/client"
  autoload :FakeClient, "conduit/fake_client"

  def self.for_you_feed(user:, request_id: nil, filter: nil, disable_conduit_cache: false, exp_context: nil, cap_filter: nil)

    begin
      response = GitHub.conduit_client.get_for_you_feed(
        user: user,
        variants: exp_context&.variants,
        disable_cache: disable_conduit_cache,
        include_starred_relationships: !user.feature_enabled?(:conduit_starred_relationships_filter) || filter&.values["StarredRelationships"],
        event_types: filter.event_types
      )

      items = response[:items]
        .apply_filter(filter)
        .filter_feed_posts(viewer: user)
        .shuffle_repo_recs

      ranking_model_id = response[:ranking_model_id]
    rescue Client::Internal => e
      Failbot.report(e)
      items = []
      ranking_model_id = nil
    end

    Feed.new(
      user,
      viewer: user,
      render_context: :for_you,
      ignore_pagination: true,
      feed_filter: filter,
      twirp_items: items,
      exp_context: exp_context,
      ranking_model_id: ranking_model_id,
      cap_filter: cap_filter,
    ).build
  end

  module Web
    def self.for_you_feed(user:, page:, filter:, request_id:, disable_conduit_cache: false, exp_context: nil, cap_filter: nil)
      repository_subscriptions = user.feature_enabled?(:feeds_v2) ? RepositorySubscriptions.for_user(user) : []

      begin
        response = GitHub.conduit_client.get_for_you_feed(
          user: user,
          variants: exp_context&.variants,
          disable_cache: disable_conduit_cache,
          include_starred_relationships: filter&.values["StarredRelationships"],
          repository_subscriptions: repository_subscriptions,
          event_types: filter.event_types,
        )

        items = response[:items]
          .apply_filter(filter)
          .filter_feed_posts(viewer: user)
          .filter_trending_repos(viewer: user)
          .shuffle_repo_recs

        ranking_model_id = response[:ranking_model_id]
        render_context = :for_you

      rescue Client::Internal => e
        Failbot.report(e)
        items = []
        ranking_model_id = nil
        render_context = :error
      end

      Feed.new(
        user,
        viewer: user,
        render_context: render_context,
        feed_filter: filter,
        page: page,
        request_id: request_id,
        twirp_items: items,
        exp_context: exp_context,
        ranking_model_id: ranking_model_id,
        cap_filter: cap_filter,
      ).build
    end

    def self.org_feed(viewer:, org:, page:, filter:, request_id:, cap_filter: nil)
      GitHub.dogstats.distribution_time("conduit.load_org_feed") do
        response = GitHub.conduit_client.get_org_feed(
          viewer: viewer,
          org_id: org.id
        )

        items = response[:items]
        .apply_filter(filter)

        Feed.new(
          viewer,
          viewer: viewer,
          render_context: :org,
          feed_filter: filter,
          page: page,
          request_id: request_id,
          twirp_items: response[:items],
          cap_filter: cap_filter,
        ).build
      end
    end

    # Currently we're only showing feed posts on the profile feed tab
    def self.profile_feed(user:, viewer:, page:, request_id:, cap_filter: nil)
      response = GitHub.conduit_client.get_profile_feed(
        user: user,
        viewer: viewer,
      )

      Feed.new(
        user,
        viewer: viewer,
        render_context: :profile_activity,
        page: page,
        request_id: request_id,
        twirp_items: response[:items].filter_feed_posts(viewer: viewer),
        ranking_model_id: response[:ranking_model_id],
        cap_filter: cap_filter,
      ).build
    end

    def self.topic_feed(viewer:, list:, page:, filter:, request_id:, topic: nil, cap_filter: nil)
      response = GitHub.conduit_client.get_topic_feed(
        viewer: viewer,
        list: list,
        topic_id: topic&.id,
      )

      items = response[:items]
        .apply_filter(filter)
        .filter_feed_posts(viewer: viewer)
        .filter_off_topic_repos(topic)

      Feed.new(
        viewer,
        viewer: viewer,
        render_context: :list,
        feed_filter: filter,
        page: page,
        request_id: request_id,
        twirp_items: items,
        ranking_model_id: response[:ranking_model_id],
        cap_filter: cap_filter
      ).build
    end
  end

  def self.hmac_for_event_id(event_id)
    OpenSSL::HMAC.hexdigest("sha256", GitHub.conduit_hmac_key, event_id.to_s)
  end

  def self.fingerprint(route, events)
    ids = events.map(&:event_id)
    Digest::SHA256.hexdigest(route.to_s + ids.join(":"))
  end
end
