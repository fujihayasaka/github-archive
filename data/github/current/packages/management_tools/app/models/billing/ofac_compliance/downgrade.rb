# typed: true
# frozen_string_literal: true

module Billing
  class OFACCompliance
    class Downgrade
      def self.perform(user, actor:)
        new(user, actor: actor).perform
      end

      attr_reader :user, :actor

      def initialize(user, actor:)
        @user = user
        @actor = actor
      end

      def perform
        return unless user.has_any_trade_restrictions? || perform_downgrade_for_spammy_user?

        user.remove_all_payment_methods(user)

        downgrade_user_subscription

        deactivate_sponsorship_records

        destroy_metered_billing_configuration

        expire_active_coupons

        cancel_organization_invitations
      end

      private

      sig { returns(T::Boolean) }
      def perform_downgrade_for_spammy_user?
        return false unless user.user?
        return false unless user.feature_enabled?(:downgrade_spammy_user)

        user.spammy?
      end

      # Set user to free, cancel subscription items and LFS, and reset billing info
      # so as to ensure we dont attempt a synchronization, which could cause a user to be billed
      def downgrade_user_subscription
        unless user.plan.free?
          # Reset the billing info, which would force a synchronization if done through existing methods
          user.update_columns(plan: GitHub::Plan.free.to_s, billed_on: nil, billing_attempts: 0)
          user.active_subscription_items.each { |item| item.update_column(:quantity, 0) }

          if user.asset_status
            # Reset the data packs, which would force a synchronization if done through existing methods
            user.asset_status.update_columns(asset_packs: 0, data_packs: 0)
          end

          user.plan_subscriptions.each do |plan_sub|
            plan_sub.update_columns(zuora_subscription_id: nil, zuora_subscription_number: nil)
          end
        end

        if user.zuora_account?
          ::Billing::Zuora::ZeroOutInvoices.for_account(user.customer.zuora_account_id)
        end
      end

      # Deactivate the relation db records for sponsorships. Subscription item cancellation
      # takes place in #downgrade_user_subscription above, but bypasses the
      # Billing::SubscriptionItemUpdater.
      def deactivate_sponsorship_records
        sponsored = Sponsorship.where(sponsorable: user)
        sponsoring = Sponsorship.where(sponsor: user)
        sponsorships = sponsored.or(sponsoring)

        received_sponsorships = sponsorships.select { |sponsorship| sponsorship.sponsorable_id == user.id }
        GitHub::PrefillAssociations.prefill_associations(received_sponsorships, :subscription_item)

        sponsorships.each do |sponsorship|
          # Only need to deactivate subscription items for sponsorships the user is receiving, since sponsorships
          # where the user is paying will have their subscription item deactivated in #downgrade_user_subscription:
          if sponsorship.sponsorable_id == user.id
            sponsorship.subscription_item&.update_column(:quantity, 0)
          end

          sponsorship.update_column(:active, false)
        end

        listing = user.sponsors_listing
        if listing
          listing.actor = actor
          listing.ban!(banned_reason: "OFAC compliance")
        end
      end

      def destroy_metered_billing_configuration
        # The `budget` association getter is overidden to a read only record
        # for restricted users so we need to query the table directly and destroy the records that way
        Billing::Budget.where(owner: user).destroy_all
      end

      # Just expires the coupon, if we wanted to sync the account, we'd call #expire!
      def expire_active_coupons
        user.coupon_redemptions.active.find_each do |coupon_redemption|
          coupon_redemption.expire
          if coupon_redemption.save
            GitHub.dogstats.increment("coupon.expired")
          end
        end
      end

      def cancel_organization_invitations
        org_invites = OrganizationInvitation.where(invitee_id: user.id).pending.includes(:organization)

        # Preload method that will be called in #paid_plan? for each org:
        promises = org_invites.map(&:organization).compact.map(&:async_delegate_billing_to_business?)
        Promise.all(promises).sync

        org_invites_to_cancel = org_invites.select { |org_invite| org_invite.organization&.paid_plan? }

        # Prefill relations that will be called by #cancel, to avoid n+1 queries:
        GitHub::PrefillAssociations.prefill_associations(org_invites_to_cancel, [:invitee, :inviter])

        org_invites_to_cancel.each do |org_invite|
          org_invite.cancel(actor: actor, notify: false)
        end
      end
    end
  end
end
