# typed: true
# frozen_string_literal: true

class UserSessions::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  # This can be a UserSession, a partial two factor AuthenticationRecord, or
  # a sign in AuthenticationRecord. The controller determines what is rendered
  # but in general we should try to bubble up to UserSessions or sign ins
  # whenever possible as they will have a more complete history.
  attr_reader :session_or_auth_record

  # The UserSession for the request in which this view model is instantiated.
  attr_reader :current_user_session

  delegate :anomalous?, :location, :created_at, to: :session_or_auth_record

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def user_session?
    @is_session ||= begin
      unless session_or_auth_record.is_a?(UserSession) || session_or_auth_record.is_a?(AuthenticationRecord)
        raise ArgumentError, "UserSession or AuthenticationRecord required. Supplied #{session_or_auth_record.class}."
      end
      session_or_auth_record.is_a?(UserSession)
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # You cannot revoke authentication records, only sessions. The ID lookup
  # is used in calls to delete records
  def session_id
    if user_session?
      session_or_auth_record.id
    elsif !revoked?
      # The session hasn't been revoked so we can get the ID from the auth record
      session_or_auth_record.user_session_id
    else
      raise ArgumentError, "Tried to get the ID of an AuthenticationRecord"
    end
  end

  def sign_in_text
    if two_factor_partial_sign_in?
      "Attempted sign in:"
    else
      "Signed in:"
    end
  end

  def authentication_record?
    !user_session?
  end

  def two_factor_partial_sign_in?
    authentication_record? && session_or_auth_record.two_factor_partial_sign_in?
  end

  # The session is current if the user session is the same as the session
  # in the view OR if the session tied to the authentication record is the
  # same as the user session
  def current_session?
    if user_session?
      session_or_auth_record == current_user_session
    elsif !revoked?
      session_or_auth_record.user_session == current_user_session
    else
      false
    end
  end

  def sign_in_location
    @sign_in_location ||= if user_session?
      session_or_auth_record.sign_in_record&.location ||
        session_or_auth_record.location
    else
      session_or_auth_record.location
    end
  end

  def authentication_history
    @authentication_history ||= if user_session?
      [session_or_auth_record] + session_or_auth_record.authentication_records
    else
      [session_or_auth_record] + AuthenticationRecord.same_session_as(session_or_auth_record)
    end
  end

  def ip_address
    if user_session?
      session_or_auth_record.ip
    else
      session_or_auth_record.ip_address
    end
  end

  def accessed_text
    if revoked?
      "Expired on"
    else
      "Last accessed on"
    end
  end

  def accessed_at
    @accessed_at ||= if user_session?
      session_or_auth_record.accessed_at
    else
      if !revoked?
        session_or_auth_record.user_session.accessed_at
      else
        siblings = current_user.authentication_records.same_session_as(session_or_auth_record).order(:created_at)
        (siblings.last || session_or_auth_record).created_at
      end
    end
  end

  def mobile?
    return @mobile if defined?(@mobile)
    user_agent = session_or_auth_record.user_agent
    @mobile = user_agent ? !!Browser.new(user_agent)&.device&.mobile? : false
  end

  def device_display_name
    @device_display_name ||= AuthenticatedDevice.generated_display_name(Browser.new(session_or_auth_record.user_agent))
  end

  # We want to mark the session as revoked if the user session has been revoked
  def revoked?
    (authentication_record? && session_or_auth_record.associated_session_revoked?) ||
      (user_session? && session_or_auth_record.revoked_at)
  end

  # Determines if we should display an enabled revoke button
  def revokable_session?
    !current_session? && !two_factor_partial_sign_in?
  end

  # We only want to show the SAML button if the session hasn't been revoked.
  def show_saml_section?
    current_session? && external_identity_sessions.any?
  end

  # Return external identity sessions for the view, either for the user session
  # or the user session associated with the authentication record.
  def external_identity_sessions
    return ExternalIdentitySession.none unless current_session?

    if user_session?
      session_or_auth_record.external_identity_sessions.active
    elsif session_or_auth_record.user_session
      session_or_auth_record.user_session.external_identity_sessions.active
    else
      ExternalIdentitySession.none
    end
  end

  # Checks if the session has any authentication records with valid location information
  # Used to determine if we should map the location
  def location_information?
    authentication_history.any? { |record| record.location[:country_code] } ||
      !!session_or_auth_record.location[:country_code]
  end

  # Creates a JSON object containing all of the countries which as session has
  # been active in. The response is of the format:
  #
  # ````
  # {
  #   "CA": 1,
  #   "US": 1,
  #   "NL": 1
  # }
  # ````
  #
  # The number represents the number of events which took place in said country
  # since this specific map is only meant to highlight the locations which events
  # took place we pass 1 for each country where an event took place
  def map_data
    locations = authentication_history.map { |record| record.location[:country_code] }.uniq
    locations.product([1]).to_h.to_json
  end

  # Iterates over authentication records associated with a given session and
  # returns all of the country codes as a list
  def country_history
    countries = authentication_history.pluck(:country_code).compact.uniq.map!(&:upcase)
    if countries.any?
      helpers.safe_join(countries, ", ")
    end
  end

  # A more detailed description of a session location along with a tooltipped
  # flag emoji
  def location_description(location)
    return if location.nil?
    location.values_at(:city, :region_name, :country_name).compact.join(", ")
  end

  # Returns an indicator for the session status
  def session_status_indicator
    classname = "session-state-indicator float-left mt-2 mr-2 rounded "
    if revoked?
      classname += "revoked"
    elsif accessed_at > UserSession::RECENTNESS.ago
      classname += "recent"
    else
      classname += "not-recent"
    end
    helpers.tag.span class: classname, style: "height: 8px; width: 8px;"
  end

  # Returns an indicator for the session status
  def session_status_indicator_text
    if revoked?
      "revoked"
    elsif accessed_at > UserSession::RECENTNESS.ago
      "active"
    else
      "stale"
    end
  end
end
