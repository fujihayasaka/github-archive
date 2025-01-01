# typed: true
# frozen_string_literal: true

class Hook::Event::SecretScanningAlertLocationEvent < Hook::Event
  extend T::Sig
  include GitHub::Memoizer

  supports_targets(*DEFAULT_TARGETS)

  description "Secrets scanning alert location created"

  event_attr :action, :repository_id, :alert_number, :location_id, required: true

  def target_repository
    @repository ||= with_read { Repository.find_by(id: repository_id) }
  end

  def target_organization
    owner = with_read { target_repository.owner }
    owner.organization? ? owner : nil
  end

  def location
    @location ||= get_location
  end

  sig { returns(T.nilable(GitHub::TokenScanning::Service::Token)) }
  memoize def secret
    get_alert
  end

  sig { returns(T.nilable(GitHub::TokenScanning::Service::Token)) }
  def get_alert
    token = get_response_from_service&.data&.token
    return nil if token.nil?
    GitHub::TokenScanning::Service::Client.wrap_token(token, target_repository)
  end

  def get_location
    locations = get_response_from_service&.data&.locations
    return nil if locations.nil? || locations.empty?
    GitHub::TokenScanning::Service::Client.wrap_token_location(locations.first, target_repository)
  end

  sig do
    returns(T.nilable(Twirp::ClientResp[
      T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetTokenLocationsResponse)
    ]))
  end
  memoize def get_response_from_service
    GitHub::TokenScanning::Service::Client.new(actor).get_token_locations(
      repository_id: repository_id,
      token_number: alert_number,
      locations_ids_selector: ::GitHub::Proto::SecretScanning::Api::V2::TokenLocationIdsSelector.new(location_ids: [location_id]),
    )
  end

  # Maps to the 'sender' object in the event payload. For 'alert location created' events, the sender is github.
  def actor
    return @actor if defined? @actor

    @actor = with_read { User.find_by_login("github") }
  end

  def deliverable?
    !!location
  end

  private

  def with_read
    ActiveRecord::Base.connected_to(role: :reading) do
      yield
    end
  end
end
