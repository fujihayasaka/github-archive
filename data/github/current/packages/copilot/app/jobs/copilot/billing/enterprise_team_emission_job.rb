# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class EnterpriseTeamEmissionJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
      extend T::Sig

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      gate_with_feature_flag :copilot_seat_emission_job

      resolve_tenant_context do |enterprise_id|
        ::Business.find(enterprise_id)
      end

      # Enterprise Teams are enough of a snowflake that we want to keep them separate from the rest of the seat emission jobs
      # Unlike the regular enterprise emission job, this enterprise has all of the seats and won't emit by organization
      # Most of this is copied from the OrganizationSeatEmissionCommand.  We will have to clean all of this up to user `owner`
      # instead of organization or business
      sig { params(enterprise_id: Integer).void }
      def perform(enterprise_id)
        chatterbox_say("Starting Copilot::Billing::EnterpriseTeamEmissionJob for enterprise #{enterprise_id}")
        GitHub.logger.with_named_tags(
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.business.id" => enterprise_id,
        ) do
          # load up the ENTERPRISE - this is required so if it isn't there, report an exception. We might want to tweak this later
          enterprise = T.let(::Business.find_by(id: enterprise_id), T.nilable(::Business))

          return handle_copilot_error(Copilot::Errors::SeatEmissionError.new("Invalid Enterprise"), { "gh.business.id" => enterprise_id }) unless enterprise

          copilot_business = Copilot::Business.new(enterprise)
          emittable_details = Copilot::Billing::Emittable.new(enterprise)

          GitHub.logger.info("Checking if enterprise has seats to emit")

          if emittable_details.seat_count.zero?
            Copilot::Instrumenter.instrument_copilot_for_business_seat_emission_skipped(
              enterprise,
              "no_seats"
            )
            GitHub.dogstats.increment("copilot.billing.enterprise_team_emission_job.no_seats")
            GitHub.logger.info("Enterprise has no seats to emit")
            return
          end

          GitHub.logger.info("Enterprise has seats to emit", "gh.copilot.seat_emission.seat_count" => emittable_details.seat_count)

          if Copilot::SeatEmission.enterprise_can_emit?(enterprise, allow_cleanup: true)
            payload = emittable_details.meuse_emission_payload

            GitHub.logger.info(
              "Emitting seat emission",
              "gh.billing_cycle.days" => emittable_details.number_of_days_in_billing_cycle,
              "gh.copilot.per_seat_rate" => emittable_details.per_seat_rate,
              "gh.copilot.quantity" => emittable_details.quantity,
              "gh.copilot.meuse_payload" => payload,
            )
            GitHub.dogstats.increment("copilot.billing.enterprise_team_emission_job.emitted")

            with_write do
              emission_payload = {
                already_billed_user_ids: [],
                current_metered_billing_cycle_starts_at: enterprise.current_metered_billing_cycle_starts_at.to_date,
                next_metered_billing_cycle_starts_at: enterprise.next_metered_billing_cycle_starts_at.to_date,
                number_of_days_in_billing_cycle: emittable_details.number_of_days_in_billing_cycle,
                business_id: enterprise_id,
                per_seat_rate: emittable_details.per_seat_rate,
                seat_count: emittable_details.seat_count,
              }

              if enterprise.customer_for(:general)&.copilot_billed_on_billing_platform?
                emission_payload[:billing_platform_payload] = payload
              else
                emission_payload[:meuse_payload] = payload
              end

              # let's store this in the database first
              seat_emission = Copilot::SeatEmission.create!(
                emission: emission_payload,
                occurred_at: payload[:usage_at],
                owner: enterprise,
                quantity: payload[:quantity],
                unique_id: payload[:usage_uuid]
              )

              # don't send to Meuse if customer is billed on billing platform
              if enterprise.customer_for(:general)&.copilot_billed_on_billing_platform?

                GitHub.dogstats.increment("copilot.billing.enterprise_team_emission_command.now_billed_on_billing_platform")

                Copilot::Instrumenter.instrument_copilot_seat_emission_on_billing_platform(
                  enterprise,
                  emittable_details.product_sku_name
                )

                GitHub.logger.info(
                  "Enterprise emits prorated emissions to billing platform",
                  "gh.billing_cycle.days" => emittable_details.number_of_days_in_billing_cycle,
                  "gh.copilot.per_seat_rate" => emittable_details.per_seat_rate,
                  "gh.copilot.seats.count" => emittable_details.seat_count,
                  "gh.copilot.quantity" => emittable_details.quantity,
                )

                # We need to emit seat-by-seat for the billing platform
                seats_to_emit = emittable_details.enterprise_seats
                seats_to_emit.each do |seat|
                  seat.seat_prorated_billing_message_emission(quantity: emittable_details.per_seat_rate, sku: emittable_details.product_sku_name)
                end
              else
                # otherwise let's emit it to Meuse
                GlobalInstrumenter.instrument("meuse.metered_usage", payload)

                Copilot::Instrumenter.instrument_copilot_for_business_seat_emission(
                  enterprise,
                  seat_emission,
                  already_billed_user_ids_count: 0,
                  number_of_days_in_billing_cycle: emittable_details.number_of_days_in_billing_cycle,
                  per_seat_rate: emittable_details.per_seat_rate,
                  seat_count: emittable_details.seat_count,
                )
              end
            end
          else
            reason = if copilot_business.copilot_for_business_free?
              COPILOT_SEAT_EMISSION_ERRORS[:copilot_business_free]
            elsif copilot_business.spammy?
              COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
            elsif copilot_business.suspended?
              COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]
            elsif !copilot_business.copilot_billable?
              COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
            elsif copilot_business.copilot_disabled?
              COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
            else
              # only other reason is that it's too soon
              COPILOT_SEAT_EMISSION_ERRORS[:too_soon]
            end

            Copilot::Instrumenter.instrument_copilot_for_business_seat_emission_skipped(
              enterprise,
              T.must(reason)
            )
            # we can't emit yet
            # If the business's copilot is disabled, we'll immediately clean up Copilot in the EnterpriseCleaner.
            # Otherwise, we'll wait until the next time the SeatEmissionJob runs rather than queue this for the future
            GitHub.logger.info(
              "Enterprise cannot emit now, exiting",
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
  end
end
