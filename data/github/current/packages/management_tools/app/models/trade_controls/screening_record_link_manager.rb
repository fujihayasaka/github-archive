# typed: strict
# frozen_string_literal: true

module TradeControls
  class ScreeningRecordLinkManager

    class ScreeningRecordLinkingError < StandardError; end
    class ScreeningRecordUnlinkingError < StandardError; end

    # Public: Checks wether there is a trade screening record linked to this SToS (Standard Terms of Service) org.
    sig { params(org: Organization).returns(T::Boolean) }
    def self.stos_org_trade_screening_record_exists?(org:)
      self.billing_information(org: org).present?
    end

    # Public: Returns the trade screening record linked to this SToS (Standard Terms of Service) org.
    #
    # If the associated record doesn't exist, it falls back to building a new
    # one. This ensures callers do not need the safe-navigation operator.
    sig { params(org: Organization).returns(AccountScreeningProfile) }
    def self.stos_org_trade_screening_record(org:)
      profile = self.billing_information(org: org)
      return profile if profile

      if ref_id = org.trade_screening_record_link.link_id
        # At this point the ref exists, but for some reason the profile no longer exists. Log and build a new one.
        # Log to datadog that we have a profile link to a non-existant record
        GitHub.dogstats.increment("sdn.find_linked_record.failed")

        # Log to Splunk for extra debugging info
        GitHub.logger.error("sdn.find_linked_record.failed",
          "gh.sdn_link_manager.org": org.display_login,
          "gh.sdn_link_manager.ref_id": ref_id,
        )
      else
        # If a ref does not exist, the org might have its own profile. Return the profile, if it exists.
        # This can happen if the org is in the process of updating to a corporate terms of service for example.
        # we don't want to overwrite the org record if an org doesn't have a linked record
        org_record = org.trade_screening_record(ignore_linked_record: true)
        return org_record if org_record.persisted?
      end

      org.build_trade_screening_record(owner: org)
    end

    # Public: Creates a link between a SToS (Standard Terms of Service) organization and an admin user's
    # screening record. The link allows SToS organizations to depend
    # on the admin's screening record for SDN and commercial interaction checks.
    sig { params(screening_record: AccountScreeningProfile, org: Organization).returns(T::Boolean) }
    def self.link_trade_screening_record_to_org(screening_record:, org:)
      # we don't want to allow linking when the org already has a screening record
      return false if self.stos_org_trade_screening_record_exists?(org: org)
      return false unless screening_record.owner.user?

      org.trade_screening_record_link.update(id: screening_record.id)
      self.link_billing_contact_to_org(owner: T.must(screening_record.user), org: org)

      org.customer&.update_contact_information
      TradeControls::Sdn::BillingChangesJob.perform_later(screening_record.id) unless screening_record.not_screened?

      actor = T.must(screening_record.user)
      new_id = screening_record.id
      new_status = screening_record.msft_trade_screening_status
      self.instrument_action(actor: actor, org: org, action: :LINK, new_id: new_id, new_status: new_status)

      true
    end

    # Public: Removes the link between a SToS (Standard Terms of Service) organization and an admin user's screening record
    sig { params(actor: User, org: Organization).returns(T::Boolean) }
    def self.unlink_trade_screening_record_from_org(actor:, org:)
      # we don't want to call stos_org_trade_screening_record_exists? because that will link the billing contact if it's not already linked
      # only to unlink it below
      return false unless self.linked_trade_screening_record(org: org).present?
      old_screening_record = org.trade_screening_record
      org.trade_screening_record_link.remove
      org.billing_contact_link.remove
      error = ScreeningRecordUnlinkingError.new("failed to remove linked screening record")
      contact_error = ScreeningRecordUnlinkingError.new("failed to remove linked billing contact")
      Failbot.report(error, external_id: old_screening_record.id) if self.stos_org_trade_screening_record_exists?(org: org)
      Failbot.report(contact_error, external_id: old_screening_record.id) if org.billing_contact_link.link_id.present?

      if org.has_valid_payment_method?(feature_type: :noncommercial)
        T.must(org.payment_method).clear_payment_details(actor)

        GitHub.dogstats.increment(
          "sdn.unlink_record.org_payment_method_dropped"
        )
      end

      old_id = old_screening_record.id
      old_status = old_screening_record.msft_trade_screening_status
      self.instrument_action(actor: actor, org: org, action: :UNLINK, old_id: old_id, old_status: old_status)

      true
    end

    sig { params(actor: User, org: Organization, action: Symbol, old_id: T.nilable(Integer), old_status: T.nilable(String), new_id: T.nilable(Integer), new_status: T.nilable(String)).void }
    def self.instrument_action(actor:, org:, action:, old_id: nil, old_status: nil, new_id: nil, new_status: nil)
      event_context = {
        actor: actor,
        perform: action,
        trade_screening_record_link: {},
      }
      event_context[:trade_screening_record_link][:old_id] = old_id.to_s if old_id
      event_context[:trade_screening_record_link][:old_screening_status] = old_status if old_status
      event_context[:trade_screening_record_link][:new_id] = new_id.to_s if new_id
      event_context[:trade_screening_record_link][:new_screening_status] = new_status if new_status

      org.instrument :trade_screening_record_link, event_context
    end

    sig { params(org: Organization).returns(T.nilable(AccountScreeningProfile)) }
    private_class_method def self.billing_information(org:)
      screening_record = self.linked_trade_screening_record(org: org)
      return screening_record if screening_record.blank? && org.billing_contact_link.link_id.blank?

      # if the screening record is blank, we want to remove the link to the billing contact.
      # This is because the links exist on separate clusters and we use a fallback when manipulating links so we need
      # to keep them in sync
      if screening_record.blank?
        ActiveRecord::Base.connected_to(role: :writing) do
          org.billing_contact_link.remove
        end
        return screening_record
      end

      self.link_billing_contact_to_org(owner: T.must(screening_record.user), org: org)
      screening_record
    end

    sig { params(org: Organization).returns(T.nilable(AccountScreeningProfile)) }
    private_class_method def self.linked_trade_screening_record(org:)
      ref_id = org.trade_screening_record_link.link_id
      return nil unless ref_id.present?

      AccountScreeningProfile.find_by(id: ref_id)
    end

    sig { params(owner: User, org: Organization).returns(T::Boolean) }
    private_class_method def self.link_billing_contact_to_org(owner:, org:)
      billing_contact = owner.customer&.billing_contact
      return false unless billing_contact.present?
      return false if billing_contact.id.nil?
      return true if org.billing_contact_link.link_id == billing_contact.id

      ActiveRecord::Base.connected_to(role: :writing) do
        org.billing_contact_link.update(id: billing_contact.id)
      end
    end
  end
end
