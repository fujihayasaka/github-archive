# typed: strict
# frozen_string_literal: true

module Billing::CopilotLicenseSnapshot
  extend ActiveSupport::Concern

  extend T::Helpers

  class Result < T::Struct
    const :copilot_for_business_count, Integer
    const :copilot_enterprise_count, Integer
    const :response, T.nilable(T.any(T::Hash[T.untyped, T.untyped], Billing::Platform::Api::Error, Hydro::Sink::Result))

    sig { returns(T::Boolean) }
    def error?
      resp = response
      case resp
      when Billing::Platform::Api::Error
        true
      when Hydro::Sink::Result
        !resp.success?
      else
        false
      end
    end

    sig { returns(String) }
    def error_message
      resp = response
      case resp
      when Billing::Platform::Api::Error
        resp.message.to_s
      when Hydro::Sink::Result
        resp.success? ? "" : resp.error.to_s
      else
        ""
      end
    end
  end

  # Computes copilot seat counts for a given billable owner and refreshes the
  # pooled entitlement via the billing platform API or publishes to
  # billingplatform.v1.CopilotLicenseSnapshot topic for asynchronous processing.
  #
  # owner       - A Business or Organization that owns the copilot seats.
  # customer_id - The billing customer ID for this owner.
  # async       - When true, publishes a Hydro event instead of calling the
  #               billing platform API directly. Defaults to false.
  #
  # Returns a Result containing seat counts and an API/publish response.
  # When sync, Result#response holds the billing platform API response.
  # When async, Result#response holds the Hydro::Sink::Result from publishing.
  sig { params(owner: T.any(::Business, ::Organization), customer_id: Integer, async: T::Boolean).returns(Result) }
  def refresh_copilot_license_snapshot(owner:, customer_id:, async: false)
    copilot_for_business_count, copilot_enterprise_count = copilot_seat_counts(owner)

    response = if async
      publish_copilot_license_snapshot_event(
        customer_id: customer_id,
        copilot_for_business_count: copilot_for_business_count,
        copilot_enterprise_count: copilot_enterprise_count,
      )
    else
      ::Billing::Platform::Api::Client.new.admin_refresh_pooled_entitlement(
        customer_id: customer_id,
        copilot_for_business_count: copilot_for_business_count,
        copilot_enterprise_count: copilot_enterprise_count,
      )
    end

    GitHub.dogstats.increment(
      "billing.copilot_license_snapshot.refresh",
      tags: ["mode:#{async ? "async" : "sync"}"],
    )

    Result.new(
      copilot_for_business_count: copilot_for_business_count,
      copilot_enterprise_count: copilot_enterprise_count,
      response: response,
    )
  end

  private

  sig { params(owner: T.any(::Business, ::Organization)).returns([Integer, Integer]) }
  def copilot_seat_counts(owner)
    if owner.is_a?(::Business)
      copilot_business = ::Copilot::Business.new(owner)

      if copilot_business.copilot_standalone?
        # Standalone enterprises send all seats as CFB
        emittable_details = Copilot::Billing::Emittable.new(owner)
        [emittable_details.standalone_enterprise_seats.count.count, 0]
      else
        counts = copilot_business.copilot_enabled_members_count_by_license
        [counts[:business].to_i, counts[:enterprise].to_i]
      end
    else
      emittable_details = Copilot::Billing::Emittable.new(owner)
      seat_count = emittable_details.organization_seats.count.count
      sku = emittable_details.product_sku_name

      copilot_for_business_count = sku == "copilot_for_business" ? seat_count : 0
      copilot_enterprise_count = sku == "copilot_enterprise" ? seat_count : 0
      [copilot_for_business_count, copilot_enterprise_count]
    end
  end

  sig { params(customer_id: Integer, copilot_for_business_count: Integer, copilot_enterprise_count: Integer).returns(Hydro::Sink::Result) }
  def publish_copilot_license_snapshot_event(customer_id:, copilot_for_business_count:, copilot_enterprise_count:)
    Hydro::PublishRetrier.publish(
      {
        customer_id: customer_id.to_i,
        copilot_for_business_count: copilot_for_business_count,
        copilot_enterprise_count: copilot_enterprise_count,
      },
      schema: "billingplatform.v1.CopilotLicenseSnapshot",
      publisher: GitHub.hydro_publisher,
    )
  end
end
