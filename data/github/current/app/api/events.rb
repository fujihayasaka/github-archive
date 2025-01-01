# typed: false
# frozen_string_literal: true

class Api::Events < Api::App
  include Stratocaster::Domain::Provider

  MAX_EVENTS = 300 # 10 pages of 30

  # All public events
  get "/events", operation_id: "activity/list-public-events" do
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

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

  # All Repository events
  get "/repositories/:repository_id/events", operation_id: "activity/list-repo-events" do
    control_access :list_events, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      timeline = Stratocaster::Timeline.for(stratocaster_domain.repo_event_key(repo), current_user)
      events = timeline.events(**pagination)

      if timeline.unavailable?
        deliver_empty status: 503
      else
        deliver :stratocaster_event_hash, events,
          last_modified: calc_last_modified(events),
          etag: timeline.class.fingerprint(stratocaster_domain.repo_event_key(repo), events)
      end
    end
  end

  # All Issue-related events for a Repository
  get "/repositories/:repository_id/events/issues", operation_id: :deprecated do
    control_access :list_repo_issue_events, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      timeline = Stratocaster::Timeline.for(stratocaster_domain.repo_event_key(repo, type: :issues), current_user)
      events = timeline.events(**pagination)

      if timeline.unavailable?
        deliver_empty status: 503
      else
        deliver :stratocaster_event_hash, events,
          last_modified: calc_last_modified(events),
          etag: timeline.class.fingerprint(stratocaster_domain.repo_event_key(repo, type: :issues), events)
      end
    end
  end

  # All public events for a repository's network (Repository#network_id)
  get "/networks/:owner/:repo/events", operation_id: "activity/list-public-events-for-repo-network" do
    control_access :list_network_events, resource: repo = this_repo, allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      timeline = Stratocaster::Timeline.for(stratocaster_domain.repo_event_key(repo, type: :network), current_user)
      events = timeline.events(**pagination)

      if timeline.unavailable?
        deliver_empty status: 503
      else
        deliver :stratocaster_event_hash, events,
          last_modified: calc_last_modified(events),
          etag: timeline.class.fingerprint(stratocaster_domain.repo_event_key(repo, type: :network), events)
      end
    end
  end

  # All public Organization events.
  get "/organizations/:organization_id/events", operation_id: "activity/list-public-org-events" do
    org = find_org!
    control_access :public_site_information, resource: Platform::PublicResource.new(resource: org), enforce_oauth_app_policy: false, allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

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

  # All events that a User received through watching.
  get "/user/:user_id/received_events", operation_id: "activity/list-received-events-for-user" do
    user = find_user!
    control_access :public_site_information, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
    key = if access_allowed?(:list_user_events, resource: user, allow_integrations: false, allow_user_via_granular_actor: true)
      :user_received_events
    else
      :user_public
    end
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

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

  # All events performed by a User.
  get "/user/:user_id/events", operation_id: "activity/list-events-for-authenticated-user" do
    user = find_user!
    control_access :apps_audited, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
    key = if access_allowed?(:list_user_events, resource: user, allow_integrations: false, allow_user_via_granular_actor: true)
      :actor
    else
      :actor_public
    end

    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

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

  # Public events that a User received through watching.
  get "/user/:user_id/received_events/public", operation_id: "activity/list-received-public-events-for-user" do
    user = find_user!
    control_access :public_site_information, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

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

  # Public events performed by a User.
  get "/user/:user_id/events/public", operation_id: "activity/list-public-events-for-user" do
    user = find_user!
    control_access :public_site_information, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

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

  private

  def timed_event_delivery
    start_time = Time.now
    set_poll_interval_header!
    yield
  ensure
    ms = ((Time.now - start_time) * 1000).round
    GitHub.dogstats.timing("events.deliver.full", ms)
  end

  def poll_interval
    60
  end

  def pagination_limit_exceeded?
    (current_page * per_page) > MAX_EVENTS
  end
end
