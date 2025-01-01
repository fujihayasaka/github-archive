# typed: strict
# frozen_string_literal: true

module Billing
  module ContactLinkManager
    extend T::Helpers

    class ContactLinkingError < StandardError; end
    class ContactUnlinkingError < StandardError; end

    sig { params(address_type: Symbol, org: Organization).returns(T::Boolean) }
    def self.org_has_linked_contact?(address_type:, org:)
      linked_contact(address_type:, org:).present?
    end

    # If the linked contact doesn't exist, it falls back to building a blank contact.
    # This ensures callers do not need the safe-navigation operator.
    sig { params(address_type: Symbol, org: Organization).returns(Contact) }
    def self.linked_org_contact(address_type:, org:)
      contact = linked_contact(address_type:, org:)
      return contact if contact

      if ref_id = contact_link(address_type:, org:).link_id
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
      build_blank_contact(address_type:)
    end

    # Creates a link between an organization and an admin user's contact.
    # The link allows organizations to depend on the admin's contact instead of filling out their own contact information.
    sig { params(address_type: Symbol, actor: User, org: Organization).returns(T::Boolean) }
    def self.link_contact_to_org(address_type:, actor:, org:)
      return false unless contact = actor.customer&.billing_contact
      return false unless contact.persisted?
      return false unless org.customer&.persisted?
      return false unless unlink_contact_from_org(address_type:, actor:, org:)

      ActiveRecord::Base.connected_to(role: :writing) do
        contact_link(address_type:, org:).update(id: contact.id)
        link_screening_record_to_org(owner: actor, org: org)
        contact.update_zuora_account_information(customer: org.customer)
      end

      screening_record = actor.trade_screening_record
      TradeControls::Sdn::BillingChangesJob.perform_later(screening_record.id) unless screening_record.not_screened?

      new_id = contact.id
      link_present = contact_link(address_type:, org:).link_id.present?
      contact_error = ContactLinkingError.new("failed to link #{address_type} contact")
      Failbot.report(contact_error, contact_id: new_id) unless link_present

      new_status = contact.trade_screening_status
      instrument_action(address_type:, actor:, org:, action: :LINK, new_id: new_id, new_status: new_status)

      link_present
    end

    # Removes the link between an organization and an admin user's contact
    sig { params(address_type: Symbol, actor: User, org: Organization).returns(T::Boolean) }
    def self.unlink_contact_from_org(address_type:, actor:, org:)
      ref_id = contact_link(address_type:, org:).link_id
      return true unless ref_id.present?

      ActiveRecord::Base.connected_to(role: :writing) do
        contact_link(address_type:, org:).remove
        org.trade_screening_record_link.remove
      end

      link_present = contact_link(address_type:, org:).link_id.present?
      trade_screening_link_present = org.trade_screening_record_link.link_id.present?
      contact_error = ContactUnlinkingError.new("failed to remove linked #{address_type} contact")
      trade_screening_error = TradeControls::ScreeningRecordLinkManager::ScreeningRecordUnlinkingError.new("failed to remove linked screening record")
      Failbot.report(contact_error, contact_id: ref_id) if link_present
      Failbot.report(trade_screening_error, external_id: actor.trade_screening_record.id) if trade_screening_link_present

      # TODO: revisit this as part of https://github.com/github/trade-compliance/issues/1458 adding the contact dependency
      #   This might be the wrong location for it since it kind of breaks the domain isolation
      if org.payment_method
        ActiveRecord::Base.connected_to(role: :writing) do
          T.must(org.payment_method).clear_payment_details(actor)
        end

        GitHub.dogstats.increment(
          "billing.unlink_#{address_type}_contact.org_payment_method_dropped"
        )
      end

      old_id = ref_id
      old_contact = Contact.find_by(id: ref_id)
      old_status = old_contact&.trade_screening_status
      instrument_action(address_type:, actor:, org:, action: :UNLINK, old_id: old_id, old_status: old_status)

      !link_present
    end

    sig { params(address_type: Symbol, actor: User, org: Organization, action: Symbol, old_id: T.nilable(Integer), old_status: T.nilable(String), new_id: T.nilable(Integer), new_status: T.nilable(String)).void }
    def self.instrument_action(address_type:, actor:, org:, action:, old_id: nil, old_status: nil, new_id: nil, new_status: nil)
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
      linked_contact = linked_contact_object(address_type:, org:)
      return linked_contact if linked_contact.blank? && org.trade_screening_record_link.link_id.blank?

      # if the contact is blank but there is still a screening record linked, we need to remove the link.
      # This is because the links exist on separate clusters and we use a fallback when manipulating links so we need
      # to keep them in sync
      if linked_contact.blank?
        ActiveRecord::Base.connected_to(role: :writing) do
          org.trade_screening_record_link.remove
        end
        return linked_contact
      end

      # technically at this point billable owner will always exist, and it will be a user
      # these are to appease sorbet and avoid doing `T.must(T.cast(linked_contact.billable_owner))`
      return linked_contact unless owner = linked_contact.billable_owner
      return linked_contact unless owner.is_a?(User)

      link_screening_record_to_org(owner: owner, org:)
      linked_contact
    end

    sig { params(address_type: Symbol, org: Organization).returns(T.nilable(Contact)) }
    private_class_method def self.linked_contact_object(address_type:, org:)
      ref_id = contact_link(address_type:, org:).link_id
      return nil unless ref_id.present?

      Contact.find_by(id: ref_id)
    end

    sig { params(owner: User, org: Organization).returns(T::Boolean) }
    private_class_method def self.link_screening_record_to_org(owner:, org:)
      screening_record = owner.trade_screening_record
      return false unless screening_record.persisted?
      return true if org.trade_screening_record_link.link_id == screening_record.id

      ActiveRecord::Base.connected_to(role: :writing) do
        org.trade_screening_record_link.update(id: screening_record.id)
      end
    end

    sig { params(address_type: Symbol).returns(Contact) }
    private_class_method def self.build_blank_contact(address_type:)
      case address_type
      when :billing
        Contact.new(address_type:)
      else
        raise ArgumentError, "Unsupported address type"
      end
    end
  end
end
