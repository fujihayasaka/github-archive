# typed: false
# frozen_string_literal: true

class Api::Events < Api::App
  include GitHub::Memoizer
  include ::Api::App::ProtectedResourcesFilter

  MAX_EVENTS = 300 # 10 pages of 30
  DEFAULT_PER_PAGE = 30
  MAX_AGE = 300
  NETWORK_EVENT_LIMIT = 100

  # All public events
  get "/events", operation_id: "activity/list-public-events" do
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource
    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if GitHub.conduit_enabled?
        begin
          twirp_items = GitHub.conduit_client.get_public_events(viewer:)[:items]
          events = conduit_feed_items(twirp_items, default_per_page: DEFAULT_PER_PAGE, **pagination)
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

      if GitHub.conduit_enabled?
        begin
          twirp_items = GitHub.conduit_client.get_repository_events(viewer:, repository_ids: [repo.id])[:items]
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

      if GitHub.conduit_enabled?
        begin
          twirp_items = GitHub.conduit_client.get_repository_events(
            viewer:,
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

      if GitHub.conduit_enabled?
        forked_ids = Repositories.domain.fork_ids_by_repo_id(
          repo_id: repo.id,
          limit: NETWORK_EVENT_LIMIT,
        )
        repository_ids = [repo.id].concat(forked_ids)
        begin
          twirp_items = GitHub.conduit_client.get_repository_events(viewer:, repository_ids:)[:items]
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

      if GitHub.conduit_enabled?
        begin
          twirp_items = GitHub.conduit_client.get_organization_events(
            viewer:, organization: org, public_only: true
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
    if access_allowed?(:list_user_events, resource: user, allow_integrations: true, allow_user_via_granular_actor: true)
      control_access :list_user_events, resource: user, allow_integrations: true, allow_user_via_granular_actor: true
      key = :user_received_events
    else
      control_access :public_site_information, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
      key = :user_public
    end

    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if GitHub.conduit_enabled?
        begin
          repository_subscriptions = Conduit::RepositorySubscriptions.for_user(user)

          pat_filtering_needed = viewer&.using_personal_access_token?
          conditional_access_filtering_needed = unauthorized_account_ids.any?

          if repository_subscriptions.any? && (pat_filtering_needed || conditional_access_filtering_needed)
            repo_ids = repository_subscriptions.map(&:repository_id).compact.uniq
            repositories = Repositories::Public.load_repositories(repo_ids)
            repositories = repositories.includes(:owner) if pat_filtering_needed
            repo_lookup = repositories.index_by(&:id)

            # when using classic PAT, remove any subscriptions where the owning organization restricts PAT access
            # see: https://github.com/github/stabilize/issues/3536
            if pat_filtering_needed
              repository_subscriptions = repository_subscriptions.reject do |subscription|
                repo = repo_lookup[subscription.repository_id]
                next true unless repo # omit if the repo was deleted after fetching subscriptions from Conduit
                next false unless repo.owner.respond_to?(:legacy_personal_access_tokens_restricted?)
                repo.owner.legacy_personal_access_tokens_restricted?
              end
            end

            if conditional_access_filtering_needed
              repository_subscriptions = repository_subscriptions.reject do |subscription|
                repo = repo_lookup[subscription.repository_id]
                next true unless repo
                unauthorized_account_ids.include?(repo.owner_id)
              end
            end
          end

          twirp_items = GitHub.conduit_client.get_user_received_events(
            viewer:,
            user:,
            public_only: key == :user_public,
            repository_subscriptions:
          )[:items]
          items = conduit_feed_items(twirp_items, default_per_page: DEFAULT_PER_PAGE, **pagination)
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
    if access_allowed?(:list_user_events, resource: user, allow_integrations: true, allow_user_via_granular_actor: true)
      control_access :list_user_events, resource: user, allow_integrations: true, allow_user_via_granular_actor: true
      key = :actor
    else
      control_access :public_site_information, resource: Platform::PublicResource.new(resource: user), allow_integrations: true, allow_user_via_granular_actor: true
      key = :actor_public
    end

    timed_event_delivery do
      deliver_pagination_cap_exceeded! if pagination_limit_exceeded?

      if GitHub.conduit_enabled?
        begin
          twirp_items = GitHub.conduit_client.get_user_events(
            viewer:, user:, public_only: key == :actor_public
          )[:items]

          if FeatureFlag.vexi.enabled?(:api_events_user_events_cap_filter, current_user, default: false) && unauthorized_account_ids.any?
            unauthorized_ids_set = unauthorized_account_ids.to_set
            twirp_items = twirp_items.reject { |item| twirp_item_from_unauthorized_owner?(item, unauthorized_ids_set) }
          end

          if FeatureFlag.vexi.enabled?(:api_events_user_events_fgpat_filter, current_user, default: false)
            fgpat_ids = fgpat_restricted_org_ids(twirp_items)
            if fgpat_ids.any?
              fgpat_ids_set = fgpat_ids.to_set
              twirp_items = twirp_items.reject { |item| twirp_item_from_unauthorized_owner?(item, fgpat_ids_set) }
            end
          end

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

      if GitHub.conduit_enabled?
        begin
          twirp_items = GitHub.conduit_client.get_organization_events(
            viewer:,
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

      if GitHub.conduit_enabled?
        begin
          repository_subscriptions = Conduit::RepositorySubscriptions.for_user(user)

          twirp_items = GitHub.conduit_client.get_user_received_events(
            viewer:,
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

      if GitHub.conduit_enabled?
        begin
          twirp_items = GitHub.conduit_client.get_user_events(
            viewer:, user:, public_only: true
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

  def conduit_feed_items(twirp_items, default_per_page: DEFAULT_PER_PAGE, **pagination)
    per_page = params[:per_page].present? ? pagination[:per_page] : default_per_page

    ::Conduit::Api::Feed.new(
      viewer,
      render_context: ::Conduit::Feed::API_CONTEXT,
      viewer:,
      twirp_items: twirp_items,
      per_page:,
      page: pagination[:page] || current_page,
      cap_filter:,
    ).build.items
  end

  def timed_event_delivery
    start_time = Time.now
    set_poll_interval_header!
    yield
  ensure
    tags = ["route:#{route_pattern}"]
    ms = ((Time.now - start_time) * 1000).round
    GitHub.dogstats.timing("events.deliver.full", ms, tags:)
  end

  def poll_interval
    60
  end

  def pagination_limit_exceeded?
    (current_page * per_page) > MAX_EVENTS
  end

  memoize def viewer
    current_integration_installation || current_user
  end

  memoize def unauthorized_account_ids
    if current_user
      current_user.unauthorized_resource_ids(cap_filter)
    else
      []
    end
  end

  def fgpat_restricted_org_ids(twirp_items)
    return [] unless current_user&.using_auth_via_user_programmatic_access?

    item_owner_ids = twirp_items.filter_map { |item| twirp_item_owner_id(item) }.uniq
    return [] if item_owner_ids.empty?

    orgs = current_user.organizations.where(id: item_owner_ids).to_a
    return [] if orgs.empty?

    Configurable.preload_configuration(orgs)
    orgs.select { |org| org.personal_access_tokens_restricted? }.map(&:id)
  end

  def twirp_item_from_unauthorized_owner?(item, unauthorized_ids_set)
    owner_id = twirp_item_owner_id(item)
    owner_id.present? && unauthorized_ids_set.include?(owner_id)
  end

  # Extracts the repo owner ID directly from the proto fields on a twirp FeedItem,
  # without any DB lookups. Returns nil when the subject type has no owner info
  # (e.g. user-follow events) or when the proto lacks a repository field.
  # Some subject types expose a scalar integer `repository_owner_id` rather than a nested
  # owner object; those cases guard against the proto default of 0 (meaning unset) with an
  # explicit `> 0` check.
  def twirp_item_owner_id(item)
    case item.subject_type
    when :SUBJECT_TYPE_ISSUE
      item.issue_subject&.repository&.owner&.id
    when :SUBJECT_TYPE_PULL_REQUEST
      id = item.pull_request_subject&.repository_owner_id
      id if id&.positive?
    when :SUBJECT_TYPE_PUSH
      item.push_subject&.repository&.owner&.id
    when :SUBJECT_TYPE_DISCUSSION
      item.discussion_subject&.repository&.owner&.id
    when :SUBJECT_TYPE_PULL_REQUEST_REVIEW
      item.pull_request_review_subject&.repository&.owner&.id
    when :SUBJECT_TYPE_PULL_REQUEST_REVIEW_COMMENT
      item.pull_request_review_comment_subject&.pull_request_review&.repository&.owner&.id
    when :SUBJECT_TYPE_PULL_REQUEST_COMMENT
      item.pull_request_comment_subject&.repository&.owner&.id
    when :SUBJECT_TYPE_ISSUE_COMMENT
      item.issue_comment_subject&.repository&.owner&.id
    when :SUBJECT_TYPE_RELEASE
      item.release_subject&.repository&.owner&.id
    when :SUBJECT_TYPE_REPOSITORY
      item.repository_subject&.owner&.id
    when :SUBJECT_TYPE_WIKI_PUSH
      item.wiki_push_subject&.repository&.owner&.id
    when :SUBJECT_TYPE_USER_LIST_ITEM
      item.user_list_item_subject&.repository&.owner&.id
    when :SUBJECT_TYPE_COMMIT_COMMENT
      id = item.commit_comment_subject&.repository_owner_id
      id if id&.positive?
    end
    # :SUBJECT_TYPE_USER — follow/sponsor events, no repo, no filtering needed
  end
end
