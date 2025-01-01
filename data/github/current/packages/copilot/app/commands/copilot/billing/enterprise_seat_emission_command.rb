# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class EnterpriseSeatEmissionCommand < Command

      sig { returns(::Business) }
      attr_reader :enterprise

      sig { returns(T::Set[Integer]) }
      attr_reader :already_billed_user_ids

      sig { params(enterprise: ::Business, already_billed_user_ids: T::Set[Integer]).void }
      def initialize(enterprise, already_billed_user_ids: Set.new)
        @enterprise = enterprise
        @already_billed_user_ids = already_billed_user_ids
      end

      sig { override.void }
      def perform
        lock do
          copilot_business = Copilot::Business.new(enterprise)
          emittable_details = Copilot::Billing::Emittable.new(enterprise, already_billed_user_ids: already_billed_user_ids)
          payload = emittable_details.billing_platform_payload

          emission_payload = {
            already_billed_user_ids: already_billed_user_ids,
            current_metered_billing_cycle_starts_at: enterprise.current_metered_billing_cycle_starts_at.to_date,
            next_metered_billing_cycle_starts_at: enterprise.next_metered_billing_cycle_starts_at.to_date,
            number_of_days_in_billing_cycle: emittable_details.number_of_days_in_billing_cycle,
            business_id: enterprise.id,
            per_seat_rate: emittable_details.per_seat_rate,
            seat_count: emittable_details.seat_count,
          }

          emission_payload[:billing_platform_payload] = payload

          GitHub.logger.with_named_tags(
            "code.namespace" => "Copilot::Billing::EnterpriseSeatEmissionCommand",
            "code.function" => "perform",
            "gh.business.id" => enterprise.id,
            "gh.business.slug" => enterprise.slug,
            "gh.copilot.already_billed.user_ids" => already_billed_user_ids,
            "gh.copilot.seats.count" => emittable_details.seat_count,
          ) do
            GitHub.logger.info("Checking if enterprise can emit")
            if emittable_details.seat_count.zero?
              Copilot::Instrumenter.instrument_copilot_for_business_seat_emission_skipped(
                enterprise,
                "no_seats"
              )
              GitHub.dogstats.increment("copilot.billing.enterprise_seat_emission_command.no_seats")
              GitHub.logger.info("Enterprise has no seats to emit")
              if Copilot::Seat.for_owner(enterprise).any? && Copilot::SeatEmission.enterprise_can_emit?(enterprise)
                # In this case the enterprise has seats but they've all already been emitted
                # We should create a zero-quantity seat emission to track that we've processed this enterprise
                # We should not emit to Meuse or Billing Platform
                GitHub.logger.info("Enterprise seats have all already been emitted")
                with_write do
                  Copilot::SeatEmission.create!(
                    emission: emission_payload,
                    occurred_at: payload[:usage_at],
                    owner: enterprise,
                    quantity: payload[:quantity],
                    unique_id: payload[:usage_uuid]
                  )
                end
              end
              return
            end

            # double check that we want to run the cleaner here, we might want to bring back allow_cleanup
            if Copilot::SeatEmission.enterprise_can_emit?(enterprise)
              GitHub.logger.info(
                "Emitting seat emission",
                "gh.billing_cycle.days" => emittable_details.number_of_days_in_billing_cycle,
                "gh.copilot.per_seat_rate" => emittable_details.per_seat_rate,
                "gh.copilot.quantity" => emittable_details.quantity,
                "gh.copilot.meuse_payload" => payload,
              )
              GitHub.dogstats.increment("copilot.billing.enterprise_seat_emission_command.emitted")

              with_write do
                # let's store this in the database first
                Copilot::SeatEmission.create!(
                  emission: emission_payload,
                  occurred_at: payload[:usage_at],
                  owner: enterprise,
                  quantity: payload[:quantity],
                  unique_id: payload[:usage_uuid]
                )
              end

              # All enterprises currently emit to the billing platform.
              GitHub.dogstats.increment("copilot.billing.enterprise_seat_emission_command.now_billed_on_billing_platform")

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

              # unlike Meuse, for the billing platform we need to emit seat-by-seat
              seats_to_emit = if copilot_business.is_standalone_business?
                emittable_details.standalone_enterprise_seats
              else
                emittable_details.enterprise_seats
              end

              seats_to_emit.each do |seat|
                seat.seat_prorated_billing_message_emission(quantity: emittable_details.per_seat_rate, sku: emittable_details.product_sku_name)
              end
            else
              log_cannot_emit(copilot_business, emittable_details)
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
        lock_key = "enterprise-seat-emission-command-#{enterprise.id}"

        restraint = GitHub::Restraint.new
        restraint.lock!(lock_key, 1, 5.minutes) do
          block.call
        end
      end

      private

      sig { params(copilot_biz: Copilot::Business, emittable_details: Copilot::Billing::Emittable).void }
      def log_cannot_emit(copilot_biz, emittable_details)
        reason = if copilot_biz.copilot_for_business_free?
          COPILOT_SEAT_EMISSION_ERRORS[:copilot_business_free]
        elsif !copilot_biz.is_standalone_business? && copilot_biz.all_orgs_have_active_trial?
          COPILOT_SEAT_EMISSION_ERRORS[:free_trial]
        elsif copilot_biz.spammy?
          COPILOT_SEAT_EMISSION_ERRORS[:is_spammy]
        elsif copilot_biz.suspended?
          COPILOT_SEAT_EMISSION_ERRORS[:is_suspended]
        elsif !copilot_biz.copilot_billable?
          COPILOT_SEAT_EMISSION_ERRORS[:is_not_billable]
        elsif !copilot_biz.copilot_enabled?
          COPILOT_SEAT_EMISSION_ERRORS[:no_copilot_business]
        elsif enterprise.deleted?
          COPILOT_SEAT_EMISSION_ERRORS[:is_deleted]
        else
          # only other reason is that it's too soon
          COPILOT_SEAT_EMISSION_ERRORS[:too_soon]
        end

        Copilot::Instrumenter.instrument_copilot_for_business_seat_emission_skipped(
          copilot_biz.business_object,
          T.must(reason)
        )
        # we can't emit yet so we'll wait until the next time the SeatEmissionJob runs rather than queue this for the future
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
