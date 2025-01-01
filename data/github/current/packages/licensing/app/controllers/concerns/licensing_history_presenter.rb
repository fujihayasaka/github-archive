# typed: strict
# frozen_string_literal: true

module LicensingHistoryPresenter
  private

  DEFAULT_AVATAR_URL = "https://avatars.githubusercontent.com/u/0"

  sig { params(business: Business, current_user: T.nilable(User)).returns(T::Boolean) }
  def show_licensing_history?(business:, current_user: nil)
    if business.metered_ghe? && !business.has_active_vss_bundle? && business.feature_flag_enabled?(:metered_license_history_rollout, default: false)
      return true
    end

    if current_user&.feature_flag_enabled?(:all_license_history, default: false)
      return true
    end

    false
  end

  sig { params(history_events: T::Array[::Licensify::Services::V1::LicenseHistoryEvent]).returns(T::Hash[Symbol, T.untyped]) }
  def ghe_license_history_payload(history_events:)
    {
      changes: process_license_events(history_events),
    }
  end

  sig { params(events: T::Array[::Licensify::Services::V1::LicenseHistoryEvent]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def process_license_events(events)
    return [] if events.empty?

    grouped_events = T.let({}, T::Hash[String, T::Array[::Licensify::Services::V1::LicenseHistoryEvent]])
    actor_usernames = T.let([], T::Array[String])
    licensee_user_ids = T.let([], T::Array[String])

    events.each do |event|
      # Extract date from timestamp
      effective_date = if event.effectiveAt&.seconds
        Time.at(event.effectiveAt&.seconds).utc.to_date.to_s
      else
        Time.now.utc.to_date.to_s
      end

      # Determine event type
      event_type = normalize_event_type(event.eventType)

      # Group key combines date and type
      key = "#{effective_date}:#{event_type}"

      events = grouped_events[key] ||= []
      events << event
      grouped_events[key] = events

      actor_usernames << event.actor if event.actor.present?

      licensee = event.licensee
      if licensee
        if licensee.type == ::Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER ||
            licensee.type == ::Licensify::Services::V1::LicenseeType.lookup(::Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER)
          licensee_user_ids << licensee.id
        end
      end
    end

    users_by_id = T.let({}, T::Hash[String, ::User])
    users_by_login = T.let({}, T::Hash[String, ::User])

    ActiveRecord::Base.connected_to(role: :reading) do
      unique_licensee_ids = licensee_user_ids.uniq

      licensee_users = ::User.select(:id, :display_login).where(id: unique_licensee_ids)
      licensee_users.each do |user|
        users_by_id[user.id.to_s] = user
        users_by_login[user.display_login] = user
      end
    end

    usernames_to_fetch = actor_usernames.uniq - users_by_login.keys
    ActiveRecord::Base.connected_to(role: :reading) do
      tenant_id = GitHub::CurrentTenant.get&.id || 0

      additional_users = ::User.select(:id, :display_login).where(display_login: usernames_to_fetch, business_id: tenant_id)
      additional_users.each do |user|
        users_by_login[user.display_login] = user
      end
    end

    # Build final response
    build_license_changes_response(grouped_events, users_by_id, users_by_login)
  end

  # Helper method to normalize event type from Symbol or Integer to string
  sig { params(event_type: T.untyped).returns(String) }
  def normalize_event_type(event_type)
    # First normalize the event type to an integer value
    event_type_int = case event_type
    when Symbol
      # If it's a symbol, resolve it to the corresponding integer value
      Licensify::Services::V1::LicenseEventType.resolve(event_type)
    else
      # Otherwise use the value directly
      event_type
    end

    # Now map the integer value to a human-readable string
    case event_type_int
    when Licensify::Services::V1::LicenseEventType::LICENSE_EVENT_TYPE_ADDED
      "added"
    when Licensify::Services::V1::LicenseEventType::LICENSE_EVENT_TYPE_REMOVED
      "removed"
    else
      # Log unexpected value for debugging if it doesn't match known types
      if event_type_int != Licensify::Services::V1::LicenseEventType::LICENSE_EVENT_TYPE_UNSPECIFIED
        GitHub.logger.warn("Unknown license event type", {
          "gh.event.eventType": event_type,
          "gh.event.eventType.class": event_type.class.name,
          "gh.event.eventType.normalized": event_type_int
        })
      end
      "unspecified"
    end
  end

  # Helper method to create a detailed event structure
  sig do params(
    event: ::Licensify::Services::V1::LicenseHistoryEvent,
      users_by_id: T::Hash[String, ::User],
      users_by_login: T::Hash[String, ::User]
  ).returns(T::Hash[Symbol, T.untyped])
  end
  def create_detailed_event(event, users_by_id, users_by_login)
    licensee = event.licensee
    if licensee
      if licensee.type == ::Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER ||
        licensee.type == ::Licensify::Services::V1::LicenseeType.lookup(::Licensify::Services::V1::LicenseeType::LICENSEE_TYPE_USER)
        login = users_by_id[licensee.id]&.display_login || licensee.id
        user_avatar_url = users_by_id[licensee.id]&.primary_avatar_url || DEFAULT_AVATAR_URL
      else
        login = "(server-only) #{licensee.id}"
      end
    end

    performed_at = if event.timestamp&.seconds
      Time.at(event.timestamp&.seconds).utc.to_date.to_s
    else
      Time.now.utc.to_date.to_s
    end

    {
      id: event.id,
      user: {
        login: login,
        avatarUrl: user_avatar_url || DEFAULT_AVATAR_URL  # Default avatar, will be updated later
      },
      performedBy: user_info_from_cache(event.actor, users_by_login),
      performedAt: performed_at
    }
  end

  # Helper method to build the final license changes response
  sig do
    params(
      grouped_events: T::Hash[String, T::Array[::Licensify::Services::V1::LicenseHistoryEvent]],
      users_by_id: T::Hash[String, ::User],
      users_by_login: T::Hash[String, ::User]
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def build_license_changes_response(grouped_events, users_by_id, users_by_login)
    changes = []

    grouped_events.each do |key, events|
      actors = events.map { |event| event.actor }.compact.uniq
      primary_actor = actors.first
      additional_actors = actors[1..-1] || []

      user = primary_actor ? user_info_from_cache(primary_actor, users_by_login) : nil

      # Transform all additional actors to include avatar URLs
      additional_users = additional_actors.map do |username|
        user_info_from_cache(username, users_by_login)
      end

      effective_date, change_type = key.split(":", 2)
      detailed_events = events.map { |event| create_detailed_event(event, users_by_id, users_by_login) }

      changes << {
        id: key,
        changeType: change_type,
        licenseCount: events.size,
        effectiveDate: effective_date,
        user: user,
        additionalUsers: additional_users,
        detailedEvents: detailed_events
      }
    end

    # Sort by date, most recent first
    changes.sort_by { |change| change[:effectiveDate] }.reverse
  end

  sig { params(username: T.nilable(String), users_cache: T::Hash[String, ::User]).returns(T::Hash[Symbol, T.nilable(String)]) }
  def user_info_from_cache(username, users_cache)
    return { login: nil, avatarUrl: DEFAULT_AVATAR_URL } if username.nil?

    user = users_cache[username]

    if user
      {
        login: user.display_login,
        avatarUrl: user.primary_avatar_url
      }
    else
      {
        login: username,
        avatarUrl: DEFAULT_AVATAR_URL
      }
    end
  end
end
