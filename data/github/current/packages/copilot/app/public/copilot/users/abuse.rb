# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Users
    module Abuse
      extend T::Helpers
      include Copilot::Users::Signatures
      include GitHub::Memoizer
      include ::Billing::Stafftools

      abstract!

      # this really should never ever ever ever have an exception, but if it does, we'll just say no
      sig { override.returns(T::Boolean) }
      def spammy?
        user_object.spammy?
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Copilot::ErrorReporter.report!(Copilot::Errors::AccessCheckError.from_error(e), copilot_user: copilot_user_object)
        false
      end

      # this really should never ever ever ever have an exception, but if it does, we'll just say no
      sig { override.returns(T::Boolean) }
      def dunning?
        user_object.dunning?
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Copilot::ErrorReporter.report!(Copilot::Errors::AccessCheckError.from_error(e), copilot_user: copilot_user_object)
        false
      end

      # This is used to check if the user has any trade restrictions
      sig { override.returns(T::Boolean) }
      def trade_restricted?
        GitHub.tracer.in_span("copilot_user.trade_restricted?") do |_span|
          user_object.has_any_trade_restrictions?
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Copilot::ErrorReporter.report!(Copilot::Errors::AccessCheckError.from_error(e), copilot_user: copilot_user_object)
        false
      end

      # This method is used to check if the user is blocked from creating a free user record.
      #
      # This is done when the user has a coupon that grants them free access but they want to upgrade to a paid plan.
      sig { override.returns(T::Boolean) }
      def free_user_blocked?
        GitHub.tracer.in_span("copilot_user.free_user_blocked?") do |_span|
          user_object.feature_enabled?(:copilot_free_user_blocked)
        end
      end

      # This method is used to block the user from creating a free user record for their coupon
      #
      # This is done when the user has a coupon that grants them free access but they want to upgrade to a paid plan.
      sig { override.void }
      def free_user_block!
        user_object.enable_feature(:copilot_free_user_blocked)
      end

      # This method is used to unblock the user from creating a free user record for their coupon
      #
      # This is done when the user has a coupon that grants them free access but they want to upgrade to a paid plan.
      sig { override.void }
      def free_user_unblock!
        user_object.disable_feature(:copilot_free_user_blocked)
      end

      # This method is used to check if the user is blocked from using Copilot by staff
      # this really should never ever ever ever have an exception, but if it does, we'll just say no
      sig { override.returns(T::Boolean) }
      memoize def administrative_blocked?
        GitHub.tracer.in_span("copilot_user.administrative_blocked?") do |_span|
          Copilot::AdministrativeBlock.active.where(blockable: user_object).exists?
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        Copilot::ErrorReporter.report!(Copilot::Errors::AccessCheckError.from_error(e), copilot_user: copilot_user_object)
        false
      end

      # This method is used to administratively block the user from using Copilot by staff
      sig { override.params(actor: ::User, reason: String, skip_hammy_check: T::Boolean, send_block_email: T::Boolean, superban: T::Boolean).returns(T.nilable(Copilot::AdministrativeBlock)) }
      def administrative_block!(actor, reason = "", skip_hammy_check: false, send_block_email: false, superban: false)

        GitHub.logger.with_named_tags(
          "gh.copilot.block.reason" => reason,
          "gh.user.login" => user_object.display_login,
          "gh.actor.login" => actor.display_login,
          "gh.copilot.send_block_email" => send_block_email,
          "gh.copilot.superban" => superban) do

          # Don't trigger telemetry if user is already blocked
          if copilot_user_object.administrative_blocked?
            msg = "#{actor.display_login} attempted to block already blocked user #{user_object.display_login} for \"#{reason}\""
            GitHub::Chatterbox.client.say!(Copilot::COPILOT_BLOCK_CHANNEL, msg)
            return
          end

          # We don't want to block a hammy user - unless it's a superban
          if !skip_hammy_check && user_object.hammy? && !superban
            msg = "#{actor.display_login} could not block hammy user #{user_object.display_login} for \"#{reason}\""
            GitHub::Chatterbox.client.say!(Copilot::COPILOT_BLOCK_CHANNEL, msg)
            return
          end

          GitHub.logger.info("Blocking copilot for user")

          access_type = copilot_user_object.access_type
          block = Copilot::AdministrativeBlock.create!(blockable: user_object, actor: actor, reason: reason)

          if send_block_email
            reference_number = SecureRandom.uuid
            GitHub.logger.info(
              "Informing copilot user of admin block via SIRE",
              "gh.copilot.warn.reference_number" => reference_number,
            )

            # create actions
            incident_response_user_actions = {
              users: [{ id: user_object.id }],
              staffnote: "Notifying user of copilot access suspension.",
              notify: {
                from: "support@githubsupport.com",
                subject: "Regarding Your Copilot Access",
                template: Copilot.block_email
              }
            }

            SecurityIncidentResponseJob.perform_later(
              actor: actor,
              id: reference_number,
              incident_responses: [
                incident_response_user_actions
              ]
            )
          end

          if superban
            if user_object.has_an_active_coupon?
              free_user = Copilot::FreeUser.find_by(user_id: user_object.id)
              if free_user.present? && free_user.type.coupon_based
                user_object.expire_active_coupon(quiet: true)
                user_object.redeem_coupon("revoked", validate_active_coupon: false, actor: actor, allow_reuse: true)
              end
            end

            if payment_method = user_object.payment_method
              card_fingerprint = payment_method.card_fingerprint.to_s
              instances = PaymentMethod.with_card_fingerprint(card_fingerprint)
              if instances.count == 1
                BlockCardFingerprintAndSuspendUsers.new(card_fingerprint: card_fingerprint, actor: actor, reason: reason).call
              elsif instances.count > 1
                # iterate over the users and see if they are admin blocked
                already_blocked = instances.select do |instance|
                  user = instance.user
                  next unless user.present?
                  cop_user = Copilot::User.new(user)
                  cop_user.administrative_blocked? || user.spammy? || user.suspended? || user.disabled?
                end
                # see if the number of already blocked instances is greater than 75% of the instances
                if already_blocked.count > (instances.count * 0.75)
                  BlockCardFingerprintAndSuspendUsers.new(card_fingerprint: card_fingerprint, actor: actor, reason: reason).call
                else
                  GitHub.logger.info("Didn't block card fingerprint for copilot user. Already blocked #{already_blocked.count}; Instances count: #{instances.count}")
                end
              end
            end
          end

          Copilot::Instrumenter.instrument_administrative_block(
            copilot_user_object,
            actor,
            reason,
            access_type: access_type,
          )

          msg = "#{actor.display_login} blocked #{user_object.display_login} for \"#{reason}\""
          GitHub::Chatterbox.client.say!(Copilot::COPILOT_BLOCK_CHANNEL, msg)

          Copilot::Instrumenter.instrument_user_abuse_event(user_object, "blocked")
          block
        end
      end

      # This method is used to administratively unblock the user from using Copilot by staff
      sig { override.params(actor: ::User, reason: String, unblock_payment_method: T::Boolean).void }
      def administrative_unblock!(actor, reason = "", unblock_payment_method: false)
        latest_block = Copilot::AdministrativeBlock.active.where(blockable: user_object).order(created_at: :desc).first

        Copilot::AdministrativeBlock.active.where(blockable: user_object).update_all(state: :revoked)
        Copilot::Instrumenter.instrument_administrative_unblock(
          user_object,
          actor,
          reason,
        )

        payment_method = user_object.payment_method
        if unblock_payment_method && payment_method.present?
          card_fingerprint = payment_method.card_fingerprint.to_s
          BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: card_fingerprint, actor: actor, reason: reason, undo_consequence: true) # rubocop:disable Naming/InclusiveLanguage
        end

        msg = "#{actor.display_login} unblocked #{user_object.display_login} for \"#{reason}\""
        msg += " (Previous block by #{latest_block.actor&.display_login} for #{latest_block.reason})" if latest_block.present?
        GitHub::Chatterbox.client.say!(Copilot::COPILOT_BLOCK_CHANNEL, msg)

        Copilot::Instrumenter.instrument_user_abuse_event(user_object, "unblocked")
      end

      sig { override.returns(T::Boolean) }
      def has_been_warned?
        Copilot::AdministrativeBlock.warned.where(blockable: user_object).exists?
      end

      # This method is called when staff warns a user about abusive Copilot usage
      # Note that warning emails issued by automation don't flow through dotcom yet: https://github.com/github/copilot-abuse/issues/273
      sig { override.params(actor: ::User, reference_number: String, reason: String).returns(Copilot::AdministrativeBlock) }
      def warn_user!(actor, reference_number, reason = "Warned via SIRE")
        block = Copilot::AdministrativeBlock.create!(
          blockable: user_object,
          actor: actor,
          reason: reason,
          state: :warned,
        )

        Copilot::Instrumenter.instrument_administrative_warn(
          copilot_user_object,
          actor,
          reason,
          access_type: access_type,
        )

        msg = "#{actor.display_login} warned #{user_object.display_login} for \"#{reason}\" via SIRE (#{reference_number})"
        GitHub::Chatterbox.client.say!(Copilot::COPILOT_BLOCK_CHANNEL, msg)
        GitHub.logger.info(
          "Chatterbox sent",
          "gh.chatterbox.message" => msg,
          "gh.chatterbox.channel" => Copilot::COPILOT_BLOCK_CHANNEL,
        )
        Copilot::Instrumenter.instrument_user_abuse_event(user_object, "warned")
        block
      end
    end
  end
end
