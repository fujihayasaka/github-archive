# typed: strict
# frozen_string_literal: true

module Billing
  module ContactLinkManager
    extend T::Helpers
    extend T::Sig

    class ContactLinkingError < StandardError; end
    class ContactUnlinkingError < StandardError; end

    sig { params(address_type: Symbol, org: Organization).returns(T::Boolean) }
    def self.org_has_linked_contact?(address_type:, org:)
      self.linked_contact(address_type:, org:).present?
    end

    # If the linked contact doesn't exist, it falls back to building a blank contact.
    # This ensures callers do not need the safe-navigation operator.
    sig { params(address_type: Symbol, org: Organization).returns(Contact) }
    def self.linked_org_contact(address_type:, org:)
      contact = self.linked_contact(address_type:, org:)
      return contact if contact

      if ref_id = self.contact_link(address_type:, org:).link_id
        # At this point the ref exists, but for some reason the contact no longer exists. Log and build a new one.
        # Log to datadog that we have a contact link to a non-existant contact
        GitHub.dogstats.increment("billing.#{address_type}_contact.find_linked_contact.failed")

        # Log to Splunk for extra debugging info
        GitHub.logger.error("billing.#{address_type}_contact.find_linked_contact.failed",
          "gh.contact_link_manager.org": org.display_login,
          "gh.contact_link_manager.ref_id": ref_id,
        )
      end

      # Build a contact with no owner to avoid nil checks. This is in place of returning nil
      self.build_blank_contact(address_type:)
    end

    # Creates a link between an organization and an admin user's contact.
    # The link allows organizations to depend on the admin's contact instead of filling out their own contact information.
    sig { params(address_type: Symbol, contact: Contact, org: Organization).returns(T::Boolean) }
    def self.link_contact_to_org(address_type:, contact:, org:)
      # we don't want to allow linking when the org already has a contact
      return false if self.org_has_linked_contact?(address_type:, org:)
      return false unless contact.persisted?
      return false unless contact.billable_owner&.user?

      self.contact_link(address_type:, org:).update(id: T.must(contact.id))

      contact.update_zuora_account_information(customer: org.customer)

      actor = T.cast(contact.billable_owner, User)
      new_id = contact.id
      new_status = contact.trade_screening_status
      self.instrument_action(actor: actor, address_type:, org:, action: :LINK, new_id: new_id, new_status: new_status)

      true
    end

    # Removes the link between an organization and an admin user's contact
    sig { params(actor: User, address_type: Symbol, org: Organization).returns(T::Boolean) }
    def self.unlink_contact_from_org(actor:, address_type:, org:)
      ref_id = self.contact_link(address_type:, org:).link_id
      return false unless ref_id.present?

      self.contact_link(address_type:, org:).remove
      contact_error = ContactUnlinkingError.new("failed to remove linked #{address_type} contact")
      Failbot.report(contact_error, contact_id: ref_id)

      # TODO: revisit this as part of https://github.com/github/trade-compliance/issues/1458 adding the contact dependency
      #   This might be the wrong location for it since it kind of breaks the domain isolation
      if org.has_valid_payment_method?
        T.must(org.payment_method).clear_payment_details(actor)

        GitHub.dogstats.increment(
          "billing.unlink_#{address_type}_contact.org_payment_method_dropped"
        )
      end

      old_id = ref_id
      old_contact = Contact.find_by(id: ref_id)
      old_status = old_contact&.trade_screening_status
      self.instrument_action(actor: actor, address_type:, org:, action: :UNLINK, old_id: old_id, old_status: old_status)

      true
    end

    sig { params(actor: User, address_type: Symbol, org: Organization, action: Symbol, old_id: T.nilable(Integer), old_status: T.nilable(String), new_id: T.nilable(Integer), new_status: T.nilable(String)).void }
    def self.instrument_action(actor:, address_type:, org:, action:, old_id: nil, old_status: nil, new_id: nil, new_status: nil)
      event_context = {
        actor: actor,
        perform: action,
        contact_address_type: address_type,
        contact_link: {},
      }
      event_context[:contact_link][:old_id] = old_id.to_s if old_id
      event_context[:contact_link][:old_screening_status] = old_status if old_status
      event_context[:contact_link][:new_id] = new_id.to_s if new_id
      event_context[:contact_link][:new_screening_status] = new_status if new_status

      org.instrument :contact_link, event_context
    end

    sig { params(address_type: Symbol, org: Organization).returns(Billing::ContactLink) }
    private_class_method def self.contact_link(address_type:, org:)
      case address_type
      when :billing
        org.billing_contact_link
      else
        raise ArgumentError, "Unsupported address type"
      end
    end

    sig { params(address_type: Symbol, org: Organization).returns(T.nilable(Contact)) }
    private_class_method def self.linked_contact(address_type:, org:)
      ref_id = self.contact_link(address_type:, org:).link_id
      return nil unless ref_id.present?

      Contact.find_by(id: ref_id)
    end

    sig { params(address_type: Symbol).returns(Contact) }
    private_class_method def self.build_blank_contact(address_type:)
      case address_type
      when :billing
        Contact.new
      else
        raise ArgumentError, "Unsupported address type"
      end
    end
  end
end
