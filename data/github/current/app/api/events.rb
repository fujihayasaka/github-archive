# typed: false
# frozen_string_literal: true

class Api::Events < Api::App
  MAX_EVENTS = 300 # 10 pages of 30
  DEFAULT_PER_PAGE = 30
  MAX_AGE = 300
  NETWORK_EVENT_LIMIT = 100

  # All public events
  get "/events", operation_id: "activity/list-public-events" do
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:public_events)
        begin
          twirp_items = GitHub.conduit_client.get_public_events(viewer: current_user)[:items]
          events = conduit_feed_items(twirp_items, default_per_page: 15, **pagination)
          paginator.collection_size = twirp_items.size
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:public", "success:true"])

          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint(:public, events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:public", "success:false"])
          deliver_empty status: 503
        end
      else
        timeline = Stratocaster::Timeline.for(:public, current_user)
        events = timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(:public, events)
        end
      end
    end
  end

  # All Repository events
  get "/repositories/:repository_id/events", operation_id: "activity/list-repo-events" do
    control_access :list_events, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:repository_events)
        begin
          twirp_items = GitHub.conduit_client.get_repository_events(viewer: current_user, repository_ids: [repo.id])[:items]
          events = conduit_feed_items(twirp_items, **pagination)
          paginator.collection_size = twirp_items.size

          GitHub.dogstats.increment("conduit.events_api", tags: ["route:repo", "success:true"])

          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint("repo:#{repo.id}", events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:repo", "success:false"])
          deliver_empty status: 503
        end
      else

        timeline = Stratocaster::Timeline.for(Stratocasters.domain.repo_event_key(repo), current_user)
        events = timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(Stratocasters.domain.repo_event_key(repo), events)
        end
      end
    end
  end

  # All Issue-related events for a Repository
  get "/repositories/:repository_id/events/issues", operation_id: :deprecated do
    control_access :list_repo_issue_events, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:repository_events)
        begin
          twirp_items = GitHub.conduit_client.get_repository_events(
            viewer: current_user,
            repository_ids: [repo.id],
            issues_only: true
          )[:items]
          events = conduit_feed_items(twirp_items, **pagination)
          paginator.collection_size = twirp_items.size

          GitHub.dogstats.increment("conduit.events_api", tags: ["route:issue", "success:true"])

          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint("repo:#{repo.id}:issues", events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:issue", "success:false"])
          deliver_empty status: 503
        end
      else
        timeline = Stratocaster::Timeline.for(Stratocasters.domain.repo_event_key(repo, type: :issues), current_user)
        events = timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(Stratocasters.domain.repo_event_key(repo, type: :issues), events)
        end
      end
    end
  end

  # All public events for a repository's network (Repository#network_id)
  get "/networks/:owner/:repo/events", operation_id: "activity/list-public-events-for-repo-network" do
    control_access :list_network_events, resource: repo = this_repo, allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:repository_events)
        forked_ids = Repositories.domain.fork_ids_by_repo_id(
          repo_id: repo.id,
          limit: NETWORK_EVENT_LIMIT,
        )
        repository_ids = [repo.id].concat(forked_ids)
        begin
          twirp_items = GitHub.conduit_client.get_repository_events(viewer: current_user, repository_ids:)[:items]
          events = conduit_feed_items(twirp_items, **pagination)
          paginator.collection_size = twirp_items.size

          GitHub.dogstats.increment("conduit.events_api", tags: ["route:network", "success:true"])

          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint("repo:#{repo.id}:network", events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:network", "success:false"])
          deliver_empty status: 503
        end
      else
        timeline = Stratocaster::Timeline.for(Stratocasters.domain.repo_event_key(repo, type: :network), current_user)
        events = timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(Stratocasters.domain.repo_event_key(repo, type: :network), events)
        end
      end
    end
  end

  # All public Organization events.
  get "/organizations/:organization_id/events", operation_id: "activity/list-public-org-events" do
    org = find_org!
    control_access :public_site_information, resource: Platform::PublicResource.new(resource: org), enforce_oauth_app_policy: false, allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:organization_events)
        begin
          twirp_items = GitHub.conduit_client.get_organization_events(
            viewer: current_user, organization: org, public_only: true
          )[:items]
          events = conduit_feed_items(twirp_items, **pagination)
          paginator.collection_size = twirp_items.size

          GitHub.dogstats.increment("conduit.events_api", tags: ["route:organization", "success:true"])

          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint(org.events_key, events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:organization", "success:false"])
          deliver_empty status: 503
        end
      else
        timeline = Stratocaster::Timeline.for(org.events_key, current_user)
        events = timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(org.events_key, events)
        end
      end
    end
  end

  # All events that a User received through watching.
  get "/user/:user_id/received_events", operation_id: "activity/list-received-events-for-user" do
    user = find_user!
    control_access :public_site_information, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
    key = if access_allowed?(:list_user_events, resource: user, allow_integrations: true, allow_user_via_granular_actor: true)
      :user_received_events
    else
      :user_public
    end

    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:user_received_events)
        begin
          repository_subscriptions = Conduit::RepositorySubscriptions.for_user(user)

          twirp_items = GitHub.conduit_client.get_user_received_events(
            viewer: current_user,
            user:,
            public_only: key == :user_public,
            repository_subscriptions:
          )[:items]
          items = conduit_feed_items(twirp_items, **pagination)
          events = user.private_profile_for?(current_user) ? [] : items
          paginator.collection_size = twirp_items.size

          GitHub.dogstats.increment("conduit.events_api", tags: ["route:user_received", "success:true"])
          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint(user.events_key(type: key), events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:user_received", "success:false"])
          deliver_empty status: 503
        end
      else
        timeline = Stratocaster::Timeline.for(user.events_key(type: key), current_user)
        events = user.private_profile_for?(current_user) ? [] : timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(user.events_key(type: key), events)
        end
      end
    end
  end

  # All events performed by a User.
  get "/user/:user_id/events", operation_id: "activity/list-events-for-authenticated-user" do
    user = find_user!
    control_access :public_site_information, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
    key = if access_allowed?(:list_user_events, resource: user, allow_integrations: true, allow_user_via_granular_actor: true)
      :actor
    else
      :actor_public
    end

    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:user_events)
        begin
          twirp_items = GitHub.conduit_client.get_user_events(
            viewer: current_user, user:, public_only: key == :actor_public
          )[:items]
          events = conduit_feed_items(twirp_items, **pagination)
          paginator.collection_size = twirp_items.size

          GitHub.dogstats.increment("conduit.events_api", tags: ["route:user", "success:true"])
          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint(user.events_key(type: key), events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:user", "success:false"])
          deliver_empty status: 503
        end
      else
        timeline = Stratocaster::Timeline.for(user.events_key(type: key), current_user)
        events = user.private_profile_for?(current_user) ? [] : timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(user.events_key(type: key), events)
        end
      end
    end
  end

  # All Organization events that a User can see. Visibility is determined by
  # Team access at the time of the Event.
  get "/user/:user_id/events/orgs/:org", operation_id: "activity/list-org-events-for-authenticated-user" do
    control_access :list_user_org_events,
                   resource: user = find_user!,
                   enforce_oauth_app_policy: false,
                   organization: find_org!,
                   allow_integrations: false,
                   allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:organization_user_events)
        begin
          twirp_items = GitHub.conduit_client.get_organization_events(
            viewer: current_user,
            organization: this_organization,
            public_only: !this_organization.member?(user),
          )[:items]
          events = conduit_feed_items(twirp_items, **pagination)
          paginator.collection_size = twirp_items.size

          GitHub.dogstats.increment("conduit.events_api", tags: ["route:organization_user", "success:true"])

          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint(user.events_key(type: :org, param: this_organization), events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:organization_user", "success:false"])
          deliver_empty status: 503
        end
      else
        timeline = Stratocaster::Timeline.for(user.events_key(type: :org, param: this_organization), current_user)
        events = timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(user.events_key(type: :org, param: this_organization), events)
        end
      end
    end
  end

  # Public events that a User received through watching.
  get "/user/:user_id/received_events/public", operation_id: "activity/list-received-public-events-for-user" do
    user = find_user!
    control_access :public_site_information, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:user_received_events)
        begin
          repository_subscriptions = Conduit::RepositorySubscriptions.for_user(user)

          twirp_items = GitHub.conduit_client.get_user_received_events(
            viewer: current_user,
            user:,
            public_only: true,
            repository_subscriptions:
          )[:items]
          items = conduit_feed_items(twirp_items, **pagination)
          events = user.private_profile_for?(current_user) ? [] : items
          paginator.collection_size = twirp_items.size

          GitHub.dogstats.increment("conduit.events_api", tags: ["route:public_user_received", "success:true"])
          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint(user.events_key(type: :user_public), events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:public_user_received", "success:false"])
          deliver_empty status: 503
        end
      else
        timeline = Stratocaster::Timeline.for(user.events_key(type: :user_public), current_user)
        events = user.private_profile_for?(current_user) ? [] : timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(user.events_key(type: :user_public), events)
        end
      end
    end
  end

  # Public events performed by a User.
  get "/user/:user_id/events/public", operation_id: "activity/list-public-events-for-user" do
    user = find_user!
    control_access :public_site_information, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if use_conduit?(:user_events)
        begin
          twirp_items = GitHub.conduit_client.get_user_events(
            viewer: current_user, user:, public_only: true
          )[:items]
          events = conduit_feed_items(twirp_items, **pagination)
          paginator.collection_size = twirp_items.size

          GitHub.dogstats.increment("conduit.events_api", tags: ["route:public_user", "success:true"])
          deliver :conduit_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: Conduit.fingerprint(user.events_key(type: :actor_public), events),
            max_age: MAX_AGE
        rescue Conduit::Client::Internal
          GitHub.dogstats.increment("conduit.events_api", tags: ["route:public_user", "success:false"])
          deliver_empty status: 503
        end
      else
        timeline = Stratocaster::Timeline.for(user.events_key(type: :actor_public), current_user)
        events = user.private_profile_for?(current_user) ? [] : timeline.events(**pagination)

        if timeline.unavailable?
          deliver_empty status: 503
        else
          deliver :stratocaster_event_hash, events,
            last_modified: calc_last_modified(events),
            etag: timeline.class.fingerprint(user.events_key(type: :actor_public), events)
        end
      end
    end
  end

  private

  def use_conduit?(route)
    return false if FeatureFlag.vexi.enabled?("force_stratocaster_events_api", current_user, default: false)

    return true if FeatureFlag.vexi.enabled?("conduit_events_api", current_user, default: false)

    case route
    when :public_events
      FeatureFlag.vexi.enabled?("conduit_events_api_public_events", current_user, default: false)
    when :repository_events
      FeatureFlag.vexi.enabled?("conduit_events_api_repo_events", current_user, default: false)
    else
      FeatureFlag.vexi.enabled?("conduit_events_api_other_events", current_user, default: false)
    end
  end

  def conduit_feed_items(twirp_items, default_per_page: DEFAULT_PER_PAGE, **pagination)
    ::Conduit::Api::Feed.new(
      current_user,
      render_context: ::Conduit::Feed::API_CONTEXT,
      viewer: current_user,
      twirp_items: twirp_items,
      per_page: pagination[:per_page] || default_per_page,
      page: pagination[:page] || current_page,
    ).build.items
  end

  def timed_event_delivery
    start_time = Time.now
    set_poll_interval_header!
    yield
  ensure
    tags = [
      "route:#{route_pattern}",
      "conduit:#{FeatureFlag.vexi.enabled?("conduit_events_api", current_user, default: false)}",
    ]
    ms = ((Time.now - start_time) * 1000).round
    GitHub.dogstats.timing("events.deliver.full", ms, tags:)
  end

  def poll_interval
    60
  end

  def pagination_limit_exceeded?
    (current_page * per_page) > MAX_EVENTS
  end
end
