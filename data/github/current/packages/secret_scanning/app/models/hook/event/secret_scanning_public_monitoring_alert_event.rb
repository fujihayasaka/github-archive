# typed: strict
# frozen_string_literal: true

class Hook::Event::SecretScanningPublicMonitoringAlertEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets Business

  feature_flag :secret_scanning_public_monitoring_apis_webhooks

  description "Secret scanning public monitoring alert created."

  event_attr :action, :business_id, required: true
  event_attr :public_monitoring_alert_id, :slug, :label,
    :created_at, :repository_id, :repository_name, required: true
  event_attr :committer_email,
    :secret_author_id, :token_scan_result_id,
    :alert_number, :location_id, :attribution_method

  sig { returns(T.nilable(Business)) }
  memoize def target_business
    if business_id
      business = ::Business.find_by(id: business_id)
      return business&.tap(&:readonly!)
    end
    super
  end

  # Override to return the business for enterprise-level feature flag checks.
  sig { returns(T.nilable(Business)) }
  def feature_flag_actor
    target_business
  end

  sig { returns(T.nilable(User)) }
  def actor
    nil
  end

  sig { returns(T.nilable(Repository)) }
  memoize def target_repository
    return nil unless repository_id
    Repository.find_by(id: repository_id)
  end

  sig { returns(T.nilable(GitHub::TokenScanning::Service::TokenLocation)) }
  memoize def location
    return nil unless alert_number && location_id && target_repository

    response = GitHub::TokenScanning::Service::Client.new(actor).get_token_locations(
      repository_id: repository_id,
      token_number: alert_number,
      locations_ids_selector: ::GitHub::Proto::SecretScanning::Api::V2::TokenLocationIdsSelector.new(location_ids: [location_id]),
    )

    locations = response&.data&.locations
    return nil if locations.nil? || locations.empty?

    GitHub::TokenScanning::Service::Client.wrap_token_location(locations.first, target_repository)
  end
end
