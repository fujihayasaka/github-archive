# typed: true
# frozen_string_literal: true

Rails.configuration.after_initialize do
  module Copilot
    class Subscribers
      PRODUCT_KEY_RANK = begin
        keys = [EDU_PRODUCT_KEY, *INDIVIDUAL_PRODUCT_KEYS]
        keys.each_with_index.to_h.freeze
      end

      SUBSCRIPTION_ATTEMPTED_TIME_PADDING = 12.hours.freeze

      def attach
        return unless GitHub.copilot_enabled?

        GitHub.subscribe("coupon_redemption.expire") do |name, _start, _ending, _transaction_id, payload|
          billable_entity_id = payload[:billable_entity_id]
          billable_entity_type = payload[:billable_entity_type]
          next Copilot::Instrumentation::EventSubscriber.log_missing(missing: [:billable_entity], payload: payload, event_name: name) if billable_entity_id.nil? || billable_entity_type.nil?

          next if billable_entity_type != "User"
          coupon = Coupon.find_by(id: payload[:coupon_id])

          if coupon.blank? || Copilot::STUDENT_COUPON_CODES.include?(coupon.code)
            user = ::User.find_by(id: billable_entity_id)
            if user&.feature_flag_enabled?(:copilot_cancel_edu_sku_on_coupon_expiry, default: false)
              Copilot::SubscriptionItemExpiredCheckJob.perform_later(user_id: billable_entity_id)
            end
          end

          free_user = Copilot::FreeUser.find_by(user_id: billable_entity_id)
          next unless free_user.present?

          Copilot::FreeUserCouponCheckJob.perform_later(free_user_id: free_user.id)
        end

        GlobalInstrumenter.subscribe "billing.pay_as_you_go_charge_collected" do |event|
          payload = event.payload
          next unless payload[:product_type] == Copilot::PRODUCT_TYPE

          customer_id = payload[:customer_id]
          customer = Customer.find_by(id: customer_id)
          next if customer.nil?
          # TODO: this may have to be changed once enterprises are supported
          billable_owner = customer.billable_owner
          next unless billable_owner.is_a?(::User)

          copilot_user = Copilot::User.new(billable_owner)
          Copilot::Billing::PaymentEventEmitter.new(copilot_user).emit_overage_charge_applied(
            payment_amount_cents: payload[:amount_in_cents],
            payment_processor_transaction_id: payload[:payment_processor_transaction_id],
          )
        end

        GlobalInstrumenter.subscribe "billing.payment_method.addition" do |event|
          # we only care if this was done in the Copilot Individual signup flow.
          referrer = GitHub.context.to_hash.fetch(:referrer, "")

          if referrer&.include?("github-copilot/signup")
            payload = event.payload

            user = ::User.find_by(id: payload[:actor_id])
            if user.present?
              copilot_user = Copilot::User.new(user)
              Copilot::Instrumenter.instrument_signup_confirmed_payment(copilot_user)
            end
          end
        end

        # This events makes sure the quota reset logic only happens after transaction is successful
        GlobalInstrumenter.subscribe "billing.payment_transaction" do |event|
          payload = event.payload
          user = ::User.find_by(id: payload[:user_id])
          next unless user.present?

          # need a way to not reset quota for recurring payments, that happens on other days of the month, and
          # should only be reset on the 1st of the month if recurring
          # or when a successful upgrade, or signup happens.

          if payload[:product_type] == Copilot::PRODUCT_TYPE && payload[:success] && (is_upgrade(user, payload) || subscription_upgrade_or_create_attempted?(user, payload[:timestamp]))
            if user.feature_flag_enabled?(:copilot_delay_limited_user_destroy, default: false)
              # Clean up any limited users because they have successfully paid for a subscription.
              Copilot::LimitedUser.find_by(user_id: user.id)&.destroy
            end
            if user.feature_flag_enabled?(:copilot_delay_limiter_quota_reset, default: false)
              public_copilot_user = Copilot::Public::User.for(user)
              GitHub.logger.info("Resetting quota for user after successful transaction",
                "gh.user.id" => user.id,
                "gh.transaction.id" => payload[:transaction_id],
                "gh.product_key" => payload[:product_key],
                "gh.previous_product_key" => payload[:previous_product_key],
                "gh.chat_quota_remaining" =>  public_copilot_user.quota_percentage_remaining(feature: "chat"),
                "gh.completions_quota_remaining" =>  public_copilot_user.quota_percentage_remaining(feature: "completions"),
                "gh.premium_interactions_quota_remaining" =>  public_copilot_user.quota_percentage_remaining(feature: "premium_interactions")
              )
              Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(
                public_copilot_user,
                reset_quota: false,
                old_plan: payload[:previous_product_key].present? ? Hydro::EntitySerializer.copilot_individual_plan(payload[:previous_product_key]) : :UNKNOWN,
                new_plan: payload[:product_key].present? ? Hydro::EntitySerializer.copilot_individual_plan(payload[:product_key]) : :UNKNOWN,
              )
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
          subscribable = if event.payload[:subscribable].is_a?(::Billing::ProductUUID) && event.payload[:subscribable].product_type == Copilot::PRODUCT_TYPE
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

      GlobalInstrumenter.subscribe "repository.template_clone_complete_with_prompt" do |event|
        payload = event.payload
        actor_id = payload[:actor_id]
        repository_nwo = payload[:repository_nwo]
        problem_statement = payload[:problem_statement]
        base_ref = payload[:base_ref]
        token = payload[:token]

        next unless actor_id.present? && repository_nwo.present? && problem_statement.present?

        ::Copilot::SweAgentJob.perform_later(
          actor_id,
          nwo: repository_nwo,
          problem_statement: problem_statement,
          base_ref: base_ref,
          creation_id: "",
          event_type: "new_repository_prompt",
          token: token,
        )
      end

      private

      def is_upgrade(user, payload)
        product_rank = PRODUCT_KEY_RANK[payload[:product_key]]
        previous_product_rank = PRODUCT_KEY_RANK[payload[:previous_product_key]]

        unless product_rank && previous_product_rank
          return false
        end

        product_rank > previous_product_rank
      end

      # Even if the previous_product_key is blank, it still may be a recurring payment.
      # example case: user upgraded from pro -> pro+ on the 18th. One billing transaction comes through on the 18th for the upgrade.
      # This should trigger a quota reset.
      # Their recurring payment is always on the 20th, this will be separate transaction with no previous_product_key set
      def subscription_upgrade_or_create_attempted?(user, timestamp)
        # kind of hacky; but check to see if the user attempted subscribe before this event came through
        event_time = timestamp.present? ? Time.zone.parse(timestamp.to_s).in_time_zone("UTC") : Time.current.in_time_zone("UTC")
        subscription_attempted_at = Copilot::Cache::SubscriptionAttemptedAtClient.new(user: user).fetch { 0 }
        return false unless subscription_attempted_at > 0
        Time.at(subscription_attempted_at).in_time_zone("UTC").between?(event_time - SUBSCRIPTION_ATTEMPTED_TIME_PADDING, event_time + 1.minute)
      end

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
              Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.for(copilot_user.user_object))
              send_cancellation_to_eloqua(user)
            elsif old_subscribable.id == new_subscribable.id
              # They are changing their subscribable
              if old_quantity == 1 && new_quantity == 0
                # They are cancelling their plan
                Copilot::Instrumenter.instrument_subscription_cancelled(
                  copilot_user, new_subscribable.billing_cycle, in_trial: copilot_user.has_trial_subscription?
                )
                Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.for(copilot_user.user_object))
                send_cancellation_to_eloqua(user)
              end
            end
          end
        end
      end

      def process_free_trial_conversion_event(event)
        # so, there is a chance that this event is for a user that is not a copilot user.
        # we are going to check that here
        subscribable = if event.payload[:subscribable].is_a?(::Billing::ProductUUID) && event.payload[:subscribable].product_type == Copilot::PRODUCT_TYPE
          event.payload[:subscribable]
        end

        if subscribable.present?
          actor_id = event.payload[:actor_id]
          user = ::User.find_by(id: actor_id)
          if user.present?
            copilot_user = Copilot::User.new(user)
            Copilot::Instrumenter.instrument_trial_subscription_converts(copilot_user, subscribable.billing_cycle)
            Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.for(copilot_user.user_object))
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
