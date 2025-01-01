# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ContactLinkManagerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  LINK_MANAGER = Billing::ContactLinkManager

  setup do
    skip unless GitHub.billing_enabled?

    @user = create(:credit_card_user)
    @contact = create(:billing_contact, customer: @user.customer)
    @org = create(:credit_card_organization, admin: @user)
  end


  context "#org_has_linked_contact?" do
    context "billing contact" do
      test "returns true if a linked contact exists" do
        assert @org.billing_contact_link.update(id: @contact.id)

        assert LINK_MANAGER.org_has_linked_contact?(address_type: :billing, org: @org)
      end

      test "returns false if no contact is linked" do
        refute LINK_MANAGER.org_has_linked_contact?(address_type: :billing, org: @org)
      end

      test "returns false if a deleted contact is linked" do
        assert @org.billing_contact_link.update(id: @contact.id)
        @contact.delete

        refute LINK_MANAGER.org_has_linked_contact?(address_type: :billing, org: @org)

        assert_predicate @org.billing_contact_link.link_id, :present?
      end
    end

    context "shipping contact" do
      test "raises unsupported error" do
        assert_raises_with_message(ArgumentError, "Unsupported address type") do
          LINK_MANAGER.org_has_linked_contact?(address_type: :shipping, org: @org)
        end
      end
    end
  end

  context "#linked_org_contact" do
    context "billing contact" do
      test "returns the linked contact" do
        assert @org.billing_contact_link.update(id: @contact.id)

        assert_equal @contact, LINK_MANAGER.linked_org_contact(address_type: :billing, org: @org)
      end

      test "returns a blank contact if the org does not have a linked contact" do
        contact = LINK_MANAGER.linked_org_contact(address_type: :billing, org: @org)

        refute_predicate @org.billing_contact_link.link_id, :present?
        refute_predicate contact, :persisted?
        assert_nil contact.id
        assert_nil contact.customer_id
        assert_nil contact.address_type
      end

      test "returns a blank contact if there's no existing customer" do
        org = create(:organization)
        contact = LINK_MANAGER.linked_org_contact(address_type: :billing, org: org)

        # No contact can be created without a customer
        refute_predicate @org.billing_contact_link.link_id, :present?
        refute_predicate contact, :persisted?
        assert_nil contact.id
        assert_nil contact.customer_id
        assert_nil contact.address_type
      end

      test "creates a blank contact if the linked contact has been deleted and log the broken link ref" do
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)

        assert @org.billing_contact_link.update(id: @contact.id)

        # Delete the contact so as not to trigger callbacks
        #   and ensure the link still exists
        @contact.delete
        assert link_id = @org.billing_contact_link.link_id

        expected_log = {
          "Body" => "billing.billing_contact.find_linked_contact.failed",
          "gh.contact_link_manager.org" => @org.display_login,
          "gh.contact_link_manager.ref_id" => link_id,
        }

        assert_logged(**expected_log) do
          @new_contact = LINK_MANAGER.linked_org_contact(address_type: :billing, org: @org)
        end

        assert_dogstats_increment 1, "billing.billing_contact.find_linked_contact.failed"

        # Check that a new contact has been created
        refute_equal @contact, @new_contact
        refute @new_contact.persisted?
        assert_predicate @org.billing_contact_link.link_id, :present?
      end
    end

    context "shipping contact" do
      test "raises unsupported error" do
        assert_raises_with_message(ArgumentError, "Unsupported address type") do
          LINK_MANAGER.linked_org_contact(address_type: :shipping, org: @org)
        end
      end
    end
  end

  context "#link_contact_to_org" do
    context "billing contact" do
      test "returns true after linking the contact" do
        Billing::Contact.any_instance.expects(:update_zuora_account_information).once

        assert LINK_MANAGER.link_contact_to_org(address_type: :billing, contact: @contact, org: @org)

        assert_predicate @org.billing_contact_link.link_id, :present?
        assert_equal @org.billing_contact_link.link_id, @contact.id
      end

      test "returns false if there's already a contact linked" do
        contact = create(:billing_contact)
        assert LINK_MANAGER.link_contact_to_org(address_type: :billing, contact: @contact, org: @org)
        Billing::Contact.any_instance.expects(:update_zuora_account_information).never

        refute LINK_MANAGER.link_contact_to_org(address_type: :billing, contact: contact, org: @org)

        assert_predicate @org.billing_contact_link.link_id, :present?
        assert_equal @org.billing_contact_link.link_id, @contact.id
      end

      test "returns false if the contact is not persisted" do
        contact = build(:billing_contact)
        Billing::Contact.any_instance.expects(:update_zuora_account_information).never

        refute LINK_MANAGER.link_contact_to_org(address_type: :billing, contact: contact, org: @org)

        refute_predicate @org.billing_contact_link.link_id, :present?
      end
    end

    context "shipping contact" do
      test "raises unsupported error" do
        Billing::Contact.any_instance.expects(:update_zuora_account_information).never

        assert_raises_with_message(ArgumentError, "Unsupported address type") do
          LINK_MANAGER.link_contact_to_org(address_type: :shipping, contact: @contact, org: @org)
        end
      end
    end
  end

  context "#unlink_contact_from_org" do
    context "billing contact" do
      test "returns true after unlinking the contact" do
        assert @org.billing_contact_link.update(id: @contact.id)
        assert_predicate @org.billing_contact_link.link_id, :present?

        assert LINK_MANAGER.unlink_contact_from_org(actor: @user, address_type: :billing, org: @org)

        refute_predicate @org.billing_contact_link.link_id, :present?
      end

      test "returns false if there's no contact linked" do
        refute LINK_MANAGER.unlink_contact_from_org(actor: @user, address_type: :billing, org: @org)

        refute_predicate @org.billing_contact_link.link_id, :present?
      end
    end

    context "shipping contact" do
      test "raises unsupported error" do
        assert_raises_with_message(ArgumentError, "Unsupported address type") do
          LINK_MANAGER.unlink_contact_from_org(actor: @user, address_type: :shipping, org: @org)
        end
      end
    end
  end
end
