# typed: strict
# frozen_string_literal: true

module Copilot
  module Abuse
    extend T::Helpers
    include CopilotBlockHelper

    sig { returns(T::Boolean) }
    def shares_payment_method_with_blocked_user?
      blocked_users_count = blocked_users_with_same_payment_method_count
      if blocked_users_count > 0
        GitHub.logger.info(
          "Copilot entity shares payment method with blocked user",
          "gh.copilot.entity_type" => configurable_object.class,
          "gh.copilot.entity_id" => configurable_object.id,
          "gh.copilot.blocked_users_count" => blocked_users_count,
        )

        return true
      end

      false
    end

    sig { returns(T::Boolean) }
    def block_if_sharing_payment_method_with_other_blocked_users!
      return false unless configurable_object.feature_enabled?(:copilot_block_shared_payment_methods)

      return false if configurable_object.business?

      blocked_users_count = blocked_users_with_same_payment_method_count
      is_trusted = TrustTiers::Tier.for_billable_owner(configurable_object).tier == TrustTiers::Tier::TRUSTED
      return false unless blocked_users_count >= 2 || (!is_trusted && blocked_users_count >= 1)
      return false unless configurable_object.payment_method&.card_fingerprint

      block_type = blocked_users_count >= 2 ? "ban" : "warn-via-support"

      blockables = if configurable_object.user?
        [self]
      else
        configurable_object.admins.map { |admin| Copilot::User.new(admin) }
      end

      GitHub.logger.info(
        "Copilot entity shares payment method with #{blocked_users_count} or more blocked user(s), blocking",
        "gh.copilot.entity_type" => configurable_object.class,
        "gh.copilot.entity_id" => configurable_object.id,
        "gh.copilot.blocked_users_count" => blocked_users_count,
        "gh.copilot.blocking_users" => blockables.map(&:id).join(","),
      )

      GitHub.dogstats.increment("copilot.abuse.blocked_users_that_share_payment_method", tags: dogstats_tags)

      blockables.each do |blockable|
        blockable.administrative_block!(::User.staff_user,
          prefix_reason("Tried to sign up to Copilot while sharing a payment method with #{blocked_users_count} blocked user(s)", block_type),
          skip_hammy_check: false,
          send_block_email: false, # Not mentioning copilot to them via email since we're not blocking for copilot usage reasons
          superban: false # Not a superban
        )
      end

      true
    end

    # Returns the number of blocked users that share the same payment method as the configurable object (excluding the object itself)
    sig { returns(Integer) }
    def blocked_users_with_same_payment_method_count
      return 0 unless configurable_object.payment_method&.card_fingerprint?

      card_fingerprint = configurable_object.payment_method.card_fingerprint
      entity_id = configurable_object.id
      user_ids_with_same_fingerprint = PaymentMethod.with_card_fingerprint(card_fingerprint).pluck(:user_id)

      ::User.where(id: user_ids_with_same_fingerprint).to_a.count { |u| u.id != entity_id && Copilot::User.new(u).administrative_blocked? }
    end

    sig do
      params(
        details: T.nilable(String), # if this is passed in, we will send that as the message, otherwise we will build one
        url: T.nilable(String),
        is_trial_signup: T::Boolean,
        duration: T.nilable(String),
        signed_up: T::Boolean,
      ).void
    end
    def send_abuse_notification(details: nil, url: nil, is_trial_signup: false, duration: nil, signed_up: true)
      class_type = configurable_object.class.to_s

      if details.nil?
        message = StringIO.new
        message.write "#{class_type} "

        if url.present?
          message.write "[#{configurable_object.display_login}](#{url})"
        else
          message.write "#{configurable_object.display_login}"
        end

        message.write " that shares payment method with #{blocked_users_with_same_payment_method_count} blocked user(s) "

        if signed_up
          message.write "just signed up for a"
        else
          message.write "was blocked attempting to sign up for a"
        end

        if is_trial_signup
          message.write " trial"
        end

        if duration
          message.write " #{duration}"
        end
        message.write " subscription."
        details = message.string
      end

      Copilot::Helpers.force_chatterbox_say!(details, room_id: COPILOT_BLOCK_CHANNEL)

    end

    sig { returns(T::Array[String]) }
    def dogstats_tags
      ["type:#{configurable_object.class}"]
    end

    abstract!

    sig { abstract.returns(T.any(::User, ::Organization, ::Business)) }
    def configurable_object; end
  end
end
