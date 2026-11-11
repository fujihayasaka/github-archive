# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class OrganizationSeatEmissionCommand < Command
      sig { returns(::Organization) }
      attr_reader :organization

      sig { returns(T::Set[Integer]) }
      attr_reader :already_billed_user_ids

      sig { params(organization: ::Organization, already_billed_user_ids: T::Set[Integer]).void }
      def initialize(organization, already_billed_user_ids: Set.new)
        @organization            = organization
        @already_billed_user_ids = already_billed_user_ids
      end

      sig { override.void }
      def perform
        lock do
          with_read do
            copilot_organization = Copilot::Organization.new(organization)
            emittable_details = Copilot::Billing::Emittable.new(organization, already_billed_user_ids: already_billed_user_ids)
            payload = emittable_details.billing_platform_payload

            emission_payload = {
              already_billed_user_ids: already_billed_user_ids,
              current_metered_billing_cycle_starts_at: organization.current_metered_billing_cycle_starts_at.to_date,
              next_metered_billing_cycle_starts_at: organization.next_metered_billing_cycle_starts_at.to_date,
              number_of_days_in_billing_cycle: emittable_details.number_of_days_in_billing_cycle,
              organization_id: organization.id,
              per_seat_rate: emittable_details.per_seat_rate,
              seat_count: emittable_details.seat_count,
            }

            emission_payload[:billing_platform_payload] = payload

            GitHub.logger.with_named_tags(
              "code.namespace" => "Copilot::Billing::OrganizationSeatEmissionCommand",
              "code.function" => "perform",
              "gh.org.id" => organization.id,
              "gh.org.login" => organization.login,
              "gh.copilot.already_billed.user_ids" => already_billed_user_ids,
              "gh.copilot.seats.count" => emittable_details.seat_count,
            ) do
              GitHub.logger.info("Checking if organization can emit")

              if emittable_details.seat_count.zero?
                Copilot::Instrumenter.instrument_copilot_for_business_seat_emission_skipped(
                  organization,
                  "no_seats"
                )
                GitHub.dogstats.increment("copilot.billing.organization_seat_emission_command.no_seats")
                GitHub.logger.info("Organization has no seats to emit")

                if Copilot::Seat.for_organization(organization).any? && Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
                  # In this case the org has seats but they've all already been emitted as part of another org
                  # We should create a zero-quantity seat emission to track that we've processed this org and
                  # prevent it from being picked up by the `CleanupNonEmittingOrgsJob`
                  # We should not emit to Meuse or Billing Platform
                  GitHub.logger.info("Organization seats have all already been emitted")
                  with_write do
                    Copilot::SeatEmission.create!(
                      emission: emission_payload,
                      occurred_at: payload[:usage_at],
                      owner: organization,
                      quantity: payload[:quantity],
                      unique_id: payload[:usage_uuid]
                    )
                  end
                end
                return
              end

              if Copilot::SeatEmission.can_emit?(organization, allow_cleanup: true)
                GitHub.logger.info(
                  "Emitting seat emission",
                  "gh.billing_cycle.days" => emittable_details.number_of_days_in_billing_cycle,
                  "gh.copilot.per_seat_rate" => emittable_details.per_seat_rate,
                  "gh.copilot.quantity" => emittable_details.quantity,
                  "gh.copilot.meuse_payload" => payload,
                )
                GitHub.dogstats.increment("copilot.billing.organization_seat_emission_command.emitted")

                with_write do
                  # let's store this in the database first
                  Copilot::SeatEmission.create!(
                    emission: emission_payload,
                    occurred_at: payload[:usage_at],
                    owner: organization,
                    quantity: payload[:quantity],
                    unique_id: payload[:usage_uuid]
                  )
                end

                GitHub.dogstats.increment("copilot.billing.organization_seat_emission_command.now_billed_on_billing_platform")

                Copilot::Instrumenter.instrument_copilot_seat_emission_on_billing_platform(
                  organization,
                  emittable_details.product_sku_name
                )

                GitHub.logger.info(
                  "Organization emits prorated emissions to billing platform",
                  "gh.billing_cycle.days" => emittable_details.number_of_days_in_billing_cycle,
                  "gh.copilot.per_seat_rate" => emittable_details.per_seat_rate,
                  "gh.copilot.seats.count" => emittable_details.seat_count,
                  "gh.copilot.quantity" => emittable_details.quantity,
                )

                seats_to_emit = emittable_details.organization_seats
                emission_owner = emittable_details.owner

                hydro_publisher = Copilot::Billing::SeatEmissionHydroPublisher.new(owner: emission_owner)
                emitted_seat_count = 0

                hydro_publisher.publish_with_timing("copilot.billing.organization_seat_emission_command.emit_seats") do |publisher, publisher_tag|
                  seats_to_emit.each do |seat|
                    seat.seat_prorated_billing_message_emission(
                      quantity: emittable_details.per_seat_rate,
                      sku: emittable_details.product_sku_name,
                      publisher: publisher,
                      publisher_tag: publisher_tag,
                    )
                    emitted_seat_count += 1
                  end

                  GitHub.dogstats.histogram(
                    "copilot.billing.organization_seat_emission_command.emit_seats.count",
                    emitted_seat_count,
                    tags: [publisher_tag],
                  )
                end

                # Emit Hydro snapshot message for standalone orgs (not part of an enterprise).
                # Orgs that delegate billing to business are already covered by
                # EnterpriseSeatEmissionJob, so we skip them here.
                unless organization.delegate_billing_to_business?
                  emit_copilot_license_snapshot(organization, seats_to_emit, emittable_details.product_sku_name)
                end
              else
                log_cannot_emit(copilot_organization, emittable_details)
              end
            end
          end
        end
      end

      sig do
        type_parameters(:A)
          .params(block: T.proc.returns(T.type_parameter(:A)))
          .returns(T.type_parameter(:A))
      end
      def lock(&block)
        lock_key = "org-seat-emission-command-#{organization.id}"

        restraint = GitHub::Restraint.new
        restraint.lock!(lock_key, 1, 5.minutes) do
          block.call
        end
      end

      private

      sig { params(org: ::Organization, seats: ActiveRecord::Relation, sku: String).void }
      def emit_copilot_license_snapshot(org, seats, sku)
        customer_id = org.customer&.id
        return unless customer_id

        seat_count = seats.length
        return unless seat_count > 0

        copilot_for_business_count = sku == "copilot_for_business" ? seat_count : 0
        copilot_enterprise_count = sku == "copilot_enterprise" ? seat_count : 0

        return if copilot_for_business_count.zero? && copilot_enterprise_count.zero?

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

      sig { params(copilot_org: Copilot::Organization, emittable_details: Copilot::Billing::Emittable).void }
      def log_cannot_emit(copilot_org, emittable_details)
        reason = if !copilot_org.has_copilot_for_business?
          COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
        elsif copilot_org.copilot_for_business_free?
          COPILOT_SEAT_EMISSION_ERRORS[:copilot_business_free]
        elsif copilot_org.on_free_copilot_business_trial?
          COPILOT_SEAT_EMISSION_ERRORS[:free_trial]
        elsif copilot_org.spammy?
          COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
        elsif !copilot_org.copilot_billable?
          COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
        elsif organization.soft_deleted? || organization.deleted?
          COPILOT_SEAT_EMISSION_ERRORS[:is_deleted]
        else
          # only other reason is that it's too soon
          COPILOT_SEAT_EMISSION_ERRORS[:too_soon]
        end

        Copilot::Instrumenter.instrument_copilot_for_business_seat_emission_skipped(
          copilot_org.organization_object,
          T.must(reason)
        )
        # we can't emit yet so we'll wait until the next time the SeatEmissionJob runs rather than queue this for the future
        GitHub.logger.info(
          "Organization cannot emit now, exiting",
          "gh.billing_cycle.days" => emittable_details.number_of_days_in_billing_cycle,
          "gh.copilot.per_seat_rate" => emittable_details.per_seat_rate,
          "gh.copilot.seats.count" => emittable_details.seat_count,
          "gh.copilot.quantity" => emittable_details.quantity,
          "gh.copilot.reason" => reason,
        )
      end
    end
  end
end
