# typed: strict
# frozen_string_literal: true

module Licensing::BusinessUserAccount::LicensingDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { BusinessUserAccount }

  # Update the enterprise license cache when the user account is created, updated or removed.
  sig { void }
  def update_business_license_usage
    T.must(business).update_license_usage if business.present?
  end

  # Used to determine if the Business can emit billing messages to the billing vnext
  # platform. At the moment, only businesses on metered plans can emit billing messages.
  sig { returns(T.nilable(T::Boolean)) }
  def can_emit_billing_message?
    T.must(business).metered_plan?
  end

  # Used to emit the billing message to the billing vnext platform when a GHEC license is added.
  sig { returns(T.nilable(T::Boolean)) }
  def emit_added_license_billing_message
    return false unless can_emit_billing_message?

    Hydro::PublishRetrier.publish(
      create_billing_message("ghec_license_added", 1.0),
      schema: "billingplatform.v1.Usage",
      publisher: GitHub.hydro_publisher
    )
    GitHub.logger.info(
      "emitted data",
      "gh.business.ghec_seats": 1.0,
      usage_uuid: create_billing_message_uuid("ghec_license_added"),
      usage_at: Google::Protobuf::Timestamp.new(seconds: DateTime.now.utc.to_i, nanos: 0),
      entity_customer_id: T.must(business).customer_id,
      entity_actor_id: user_id,
    )
    GitHub.dogstats.increment("ghec_seats.billing_vnext.added")
    T.must(business).instrument :emit_ghec_license_added
    true
  end

  # Used to emit the billing message to the billing vnext platform when a GHEC license is removed.
  sig { returns(T.nilable(T::Boolean)) }
  def emit_removed_license_billing_message
    return false unless can_emit_billing_message?

    Hydro::PublishRetrier.publish(
      create_billing_message("ghec_license_removed", -1.0),
      schema: "billingplatform.v1.Usage",
      publisher: GitHub.hydro_publisher
    )
    GitHub.logger.info(
      "emitted data",
      "gh.business.ghec_seats": -1.0,
      usage_uuid: create_billing_message_uuid("ghec_license_removed"),
      usage_at: Google::Protobuf::Timestamp.new(seconds: DateTime.now.utc.to_i, nanos: 0),
      entity_customer_id: T.must(business).customer_id,
      entity_actor_id: user_id,
    )
    GitHub.dogstats.increment("ghec_seats.billing_vnext.removed")
    T.must(business).instrument :emit_ghec_license_removed
    true
  end

  private

  sig { void }
  def snapshot_license_state
    Licensing::SnapshotLicensesJob.perform_later(business) if business.present?
  end

  sig { void }
  def assign_user_to_bundled_license_assignment
    return if user.nil?
    return unless business&.volume_licensing_enabled?

    Licensing::SetUserFromEmailsOnBundledLicenseAssignmentJob.perform_later(
      business: T.must(business), user: T.must(user)
    )
  end

  # Used to create the billing message when a GHEC license is added or removed.
  #
  # prefix - String, either "ghec_license_added" or "ghec_license_removed".
  # quantity - Float, either 1.0 or -1.0.
  sig do
    params(prefix: String, quantity: Float).returns(
    {
      sku: String,
      quantity: Float,
      usage_at: Google::Protobuf::Timestamp,
      source_uri: String,
      usage_uuid: String,
      entity: T::Hash[String, Integer],
    })
  end
  def create_billing_message(prefix, quantity)
    {
      sku: "ghec_seats",
      quantity: quantity,
      usage_at: Google::Protobuf::Timestamp.new(seconds: DateTime.now.utc.to_i, nanos: 0),
      source_uri: GlobalID.create(T.must(business).customer).to_s,
      usage_uuid: create_billing_message_uuid(prefix),
      entity: {
        customer_id: T.must(business).customer_id,
        actor_id: user_id,
      }
    }
  end

  # The uuid used to deduplicate the billing vnext platform usage events. Since billing is
  # on a monthly cadence, if two add/remove events are emitted in the same month for the same user,
  # they are deduped based on the uuid. Each User is uniquely associated with a Customer. NB: Each
  # Business is uniquely associated with the Business.
  #
  # prefix - String, either "ghec_license_added" or "ghec_license_removed".
  sig { params(prefix: String).returns(String) }
  def create_billing_message_uuid(prefix)
    date = DateTime.now.utc
    Digest::SHA256.hexdigest(prefix + T.must(business).customer_id.to_s + ":" + user_id.to_s + ":" + date.strftime("%m/%d/%Y:%H:%M:%S")).to_s
  end
end
