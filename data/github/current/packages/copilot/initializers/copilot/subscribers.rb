# typed: true
# frozen_string_literal: true

Rails.configuration.after_initialize do
  module Copilot
    class Subscribers
      def attach
        return unless GitHub.copilot_enabled?

        GitHub.subscribe("coupon_redemption.expire") do |name, _start, _ending, _transaction_id, payload|
          billable_entity_id = payload[:billable_entity_id]
          billable_entity_type = payload[:billable_entity_type]
          next Copilot::Instrumentation::EventSubscriber.log_missing(missing: [:billable_entity], payload: payload, event_name: name) if billable_entity_id.nil? || billable_entity_type.nil?

          next if billable_entity_type != "User"

          free_user = Copilot::FreeUser.find_by(user_id: billable_entity_id)
          next unless free_user.present?

          Copilot::FreeUserCouponCheckJob.perform_later(free_user_id: free_user.id)
        end

        GlobalInstrumenter.subscribe "billing.payment_method.addition" do |event|
          # we only care if this was done in the Copilot Individual signup flow.
          referrer = GitHub.context.to_hash.fetch(:referrer, "")
          if referrer.include?("github-copilot/signup")
            payload = event.payload

            user = ::User.find_by(id: payload[:actor_id])
            if user.present?
              copilot_user = Copilot::User.new(user)
              Copilot::Instrumenter.instrument_signup_confirmed_payment(copilot_user)
            end
          end
        end

        # TODO: Handle when the duration is changed - waiting on Billing to support this
        GlobalInstrumenter.subscribe "billing.subscription_item_change" do |event|
          process_item_change_event(event)
        end

        GitHub.subscribe "billing.subscription_item_cancel_and_refund" do |event|
          process_subscription_item_refund_event(event)
        end

        GlobalInstrumenter.subscribe "billing.free_trial_conversion" do |event|
          # so, there is a chance that this event is for a user that is not a copilot user.
          # we are going to check that here
          subscribable = if event.payload[:subscribable].is_a?(::Billing::ProductUUID) && event.payload[:subscribable].product_type == "github.copilot"
            event.payload[:subscribable]
          end

          if subscribable.present?
            actor_id = event.payload[:actor_id]
            user = ::User.find_by(id: actor_id)
            if user.present?
              copilot_user = Copilot::User.new(user)
              Copilot::Instrumenter.instrument_trial_subscription_converts(copilot_user, subscribable.billing_cycle)
            end
          end
        end
      end

      GitHub.subscribe("org.delete") do |name, _start, _ending, transaction_id, payload|
        org_id = payload.fetch(:org_id)

        next Copilot::Instrumentation::EventSubscriber.log_missing(missing: [:org_id], event_name: name, payload: payload) unless org_id

        Copilot::ContentExclusion::OrganizationJob.perform_later(
          organization_id: org_id,
          action: :organization_destroyed,
          transaction_id:,
        )
      end

      private

      def process_item_change_event(event)
        old_subscribable = event.payload[:old_subscribable]

        if old_subscribable.is_a?(::Billing::ProductUUID)
          user_id = event.payload[:user_id]
          user = ::User.find_by(id: user_id)

          if user.present?
            copilot_user = Copilot::User.new(user)

            new_subscribable = event.payload[:new_subscribable]
            old_quantity     = event.payload[:old_quantity]
            new_quantity     = event.payload[:new_quantity]

            if new_subscribable.nil?
              # The subscription is being deleted
              Copilot::Instrumenter.instrument_subscription_cancelled(
                copilot_user, old_subscribable.billing_cycle, in_trial: copilot_user.has_trial_subscription?
              )
              send_cancellation_to_eloqua(user)

            elsif old_subscribable.id == new_subscribable.id
              # They are changing their subscribable
              if old_quantity == 1 && new_quantity == 0
                # They are cancelling their plan
                Copilot::Instrumenter.instrument_subscription_cancelled(
                  copilot_user, new_subscribable.billing_cycle, in_trial: copilot_user.has_trial_subscription?
                )
                send_cancellation_to_eloqua(user)
              end
            end
          end
        end
      end

      def process_free_trial_conversion_event(event)
        # so, there is a chance that this event is for a user that is not a copilot user.
        # we are going to check that here
        subscribable = if event.payload[:subscribable].is_a?(::Billing::ProductUUID) && event.payload[:subscribable].product_type == "github.copilot"
          event.payload[:subscribable]
        end

        if subscribable.present?
          actor_id = event.payload[:actor_id]
          user = ::User.find_by(id: actor_id)
          if user.present?
            copilot_user = Copilot::User.new(user)
            Copilot::Instrumenter.instrument_trial_subscription_converts(copilot_user, subscribable.billing_cycle)
          end
        end
      end

      def process_subscription_item_refund_event(event)
        unless event.payload[:product_type] == Copilot::PRODUCT_TYPE
          GitHub.logger.info("Skipping email for product type", "gh.billing.subscription_item.product_type" => event.payload[:product_type])
          return
        end

        unless event.payload[:skip_email]
          GitHub.logger.info("Skipping email because billing email was not skipped")
          return
        end

        user = ::User.find_by(id: event.payload[:user_id])
        unless user
          GitHub.logger.info("Skipping email because user was not found")
          return
        end
        user = T.must(user)

        organization = ::Organization.find_by(id: event.payload[:organization_id])
        unless organization
          GitHub.logger.info("Skipping email because organization was not found")
          return
        end
        organization = T.must(organization)

        GitHub.logger.info(
          "Sending refund email",
          "gh.user.id" => user.id,
          "gh.user.login" => user.login,
          "gh.user.email" => user.email,
          "gh.org.id" => organization.id,
          "gh.org.login" => organization.login,
          "gh.billing.subscription_item.refund_amount_in_cents" => event.payload[:refund_amount_in_cents],
        )

        case
        when event.payload[:trial_user]
          CopilotForBusinessMailer.seat_added_for_user_with_cfi_trial(
            organization,
            user,
          ).deliver_later
        when event.payload[:refund_success]
          CopilotForBusinessMailer.seat_added_for_user_with_cfi_refund(
            organization,
            user,
            event.payload[:payment_type],
            event.payload[:refund_amount_in_cents],
            event.payload[:refunded_at],
            event.payload[:sale_date],
          ).deliver_later
        else
          CopilotForBusinessMailer.seat_added_for_user(
            organization,
            user,
          ).deliver_later

          GitHub.logger.info(
            "Unknown billing.subscription_item_cancel_and_refund structure",
            "gh.copilot.event.payload" => event.payload,
          )
        end
      end

      def send_cancellation_to_eloqua(user)
        eloqua_args = {
          uri: "https://s88570519.t.eloqua.com/e/f2?elqFormName=UntitledForm-1660759955375&elqSiteId=88570519",
          email: user.email
        }
        Copilot::SendEmailToEloquaJob.perform_later(eloqua_args)
      end
    end
  end

  Copilot::Subscribers.new.attach
end
