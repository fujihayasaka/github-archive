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
            if organization.customer_for(:general, delegate_to_business: true)&.copilot_billed_on_billing_platform? || organization.business&.feature_enabled?(:skip_copilot_meuse_emission) || ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
              payload = emittable_details.billing_platform_payload
            else
              payload = emittable_details.meuse_emission_payload
            end

            emission_payload = {
              already_billed_user_ids: already_billed_user_ids,
              current_metered_billing_cycle_starts_at: organization.current_metered_billing_cycle_starts_at.to_date,
              next_metered_billing_cycle_starts_at: organization.next_metered_billing_cycle_starts_at.to_date,
              number_of_days_in_billing_cycle: emittable_details.number_of_days_in_billing_cycle,
              organization_id: organization.id,
              per_seat_rate: emittable_details.per_seat_rate,
              seat_count: emittable_details.seat_count,
            }

            if organization.customer_for(:general, delegate_to_business: true)&.copilot_billed_on_billing_platform? || organization.business&.feature_enabled?(:skip_copilot_meuse_emission) || ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
              emission_payload[:billing_platform_payload] = payload
            else
              emission_payload[:meuse_payload] = payload
            end

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

                seat_emission = with_write do
                  # let's store this in the database first
                  Copilot::SeatEmission.create!(
                    emission: emission_payload,
                    occurred_at: payload[:usage_at],
                    owner: organization,
                    quantity: payload[:quantity],
                    unique_id: payload[:usage_uuid]
                  )
                end

                # don't send to Meuse if customer's copilot is now billed on billing platform
                if organization.customer_for(:general, delegate_to_business: true)&.copilot_billed_on_billing_platform? || organization.business&.feature_enabled?(:skip_copilot_meuse_emission) || ::FeatureFlag.vexi.enabled?(:cutoff_emissions_to_meuse, default: false)
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

                  # unlike Meuse, for the billing platform we need to emit seat-by-seat
                  seats_to_emit = emittable_details.organization_seats
                  seats_to_emit.each do |seat|
                    seat.seat_prorated_billing_message_emission(quantity: emittable_details.per_seat_rate, sku: emittable_details.product_sku_name)
                  end
                else
                  # now let's emit it to Meuse
                  GlobalInstrumenter.instrument("meuse.metered_usage", payload)

                  Copilot::Instrumenter.instrument_copilot_for_business_seat_emission(
                    organization,
                    seat_emission,
                    already_billed_user_ids_count: already_billed_user_ids.count,
                    number_of_days_in_billing_cycle: emittable_details.number_of_days_in_billing_cycle,
                    per_seat_rate: emittable_details.per_seat_rate,
                    seat_count: emittable_details.seat_count,
                  )
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
