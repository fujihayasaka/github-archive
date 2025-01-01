# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ContactTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include Billing::AddressLookupTestHelpers

  fixtures do
    skip unless GitHub.billing_enabled?

    GitHub.flipper[:read_billing_information_from_contacts].enable
    @user = create(:credit_card_user)
    @org = create(:credit_card_org)
    @business = create(:business)
  end

  context "validations" do
    test "doesn't allow multiple contacts of the same address type" do
      billing_contact = T.let(create(:billing_contact), Billing::Contact)
      customer = T.must(billing_contact.customer)
      shipping_contact = create(:shipping_contact, customer: customer)
      assert_predicate billing_contact, :valid?
      assert_predicate shipping_contact, :valid?
      assert_predicate customer.reload, :valid?

      billing_contact2 = build(:billing_contact, customer: customer)

      refute_predicate billing_contact2, :valid?
      assert_includes billing_contact2.errors.full_messages, "Address type has already been taken"
    end

    test "doesn't allow contacts for standard terms org" do
      @org = create(:credit_card_org)
      contact = build(:billing_contact, :with_org, customer: @org.customer)

      refute_predicate contact, :valid?
      assert_includes contact.errors.full_messages, "Organizations on standard terms of service can only have a linked Contact record to the user"
    end

    test "doesn't allow both first/last name and entity name to be provided" do
      contact = build(:billing_contact)
      contact.entity_name = "GitHub"

      refute_predicate contact, :valid?
      assert_includes contact.errors.full_messages, "Entity name cannot be provided if first name or last name is present"
    end

    test "allows partial contacts to be saved" do
      contact = Billing::Contact.create(address_type: :billing, customer: @user.customer, first_name: "John")

      assert_predicate contact, :valid?
      assert_predicate contact, :persisted?
    end
  end

  context "#fullname" do
    test "returns successfully for partial record with first name only" do
      contact = Billing::Contact.create(address_type: :billing, customer: @user.customer, first_name: "John")

      assert_equal "John", contact.fullname
    end

    test "returns successfully for partial record with last name only" do
      contact = Billing::Contact.create(address_type: :billing, customer: @user.customer, last_name: "Miller")

      assert_equal "Miller", contact.fullname
    end

    test "returns successfully for partial record with entity name" do
      contact = Billing::Contact.create(address_type: :billing, customer: @user.customer, entity_name: "Adventure Society")

      assert_equal "Adventure Society", contact.fullname
    end

    test "returns successfully when first/last/entity name are all nil" do
      contact = Billing::Contact.create(address_type: :billing, customer: @user.customer)

      assert_predicate contact.fullname, :blank?
    end
  end

  context "#update_zuora_account_information" do
    test "enqueues UpdateZuoraAccountInformationJob on creation" do
      Customer.any_instance.expects(:update_contact_information).returns(true)

      assert_enqueued_jobs(1, only: UpdateZuoraAccountInformationJob) do
        create(:billing_contact, customer: @user.customer)
      end
    end

    test "enqueues UpdateZuoraAccountInformationJob on update" do
      contact = create(:billing_contact, customer: @user.customer)
      Customer.any_instance.expects(:update_contact_information).with { |c| c.id == contact.id }.returns(true)

      assert_enqueued_jobs(1, only: UpdateZuoraAccountInformationJob) do
        contact.update!(postal_code: "12345")
      end

      assert_enqueued_with(job: UpdateZuoraAccountInformationJob, args: [{ zuora_account_id: @user.customer.zuora_account_id, contact_id: contact.id, }])
    end

    test "enqueues UpdateZuoraAccountInformationJob for each linked org" do
      contact = create(:billing_contact, customer: @user.customer)
      org1 = create(:credit_card_org, admin: @user)
      org2 = create(:credit_card_org, admin: @user)
      org3 = create(:credit_card_org, admin: @user)
      org4 = create(:credit_card_org, admin: @user)
      org1.billing_contact_link.update(id: contact.id)
      org2.billing_contact_link.update(id: contact.id)
      org3.billing_contact_link.update(id: contact.id)

      Customer.any_instance.expects(:update_contact_information).with { |c| c.id == contact.id }.times(4).returns(true)

      assert_enqueued_jobs(4, only: UpdateZuoraAccountInformationJob) do
        contact.update!(postal_code: "12345")
      end


      assert_enqueued_with(job: UpdateZuoraAccountInformationJob, args: [{ zuora_account_id: @user.customer.zuora_account_id, contact_id: contact.id, }])
      assert_enqueued_with(job: UpdateZuoraAccountInformationJob, args: [{ zuora_account_id: org1.customer.zuora_account_id, contact_id: contact.id, }])
      assert_enqueued_with(job: UpdateZuoraAccountInformationJob, args: [{ zuora_account_id: org2.customer.zuora_account_id, contact_id: contact.id, }])
      assert_enqueued_with(job: UpdateZuoraAccountInformationJob, args: [{ zuora_account_id: org3.customer.zuora_account_id, contact_id: contact.id, }])
    end

    test "does not enqueue for org if it's not linked" do
      contact = create(:billing_contact, customer: @user.customer)
      org = create(:credit_card_org, admin: @user)

      Billing::Contact.any_instance.expects(:update_zuora_account_information).once

      contact.update!(postal_code: "12345")
    end

    test "does not enqueue for a linked org that doesn't have a customer" do
      contact = create(:billing_contact, customer: @user.customer)
      org = create(:organization, admin: @user)
      org.billing_contact_link.update(id: contact.id)

      Billing::Contact.any_instance.expects(:update_zuora_account_information).once
      Customer.any_instance.expects(:update_contact_information).never
      UpdateZuoraAccountInformationJob.expects(:perform_later).never

      contact.update!(postal_code: "12345")
    end

    test "does not enqueue for a linked org if the address type is not billing" do
      contact = create(:billing_contact, customer: @user.customer)
      org = create(:credit_card_org, admin: @user)
      org.billing_contact_link.update(id: contact.id)
      shipping_contact = create(:shipping_contact, customer: @user.customer)

      Billing::Contact.any_instance.expects(:update_zuora_account_information).once

      shipping_contact.update!(postal_code: "12345")
    end
  end

  context "#instrumentation" do
    test "instrumentation is triggered when a contact is created" do
      assert_performed_audit_entries(count: 1, only: "billing.contact_create") do
        contact = create(:shipping_contact)
      end
    end

    test "instrumentation is triggered when a contact is updated" do
      contact = create(:billing_contact)

      assert_performed_audit_entries(count: 1, only: "billing.contact_update") do
        contact.first_name = "John"
        contact.save!
      end
    end

    test "instrumentation is triggered when a contact is destroyed" do
      contact = create(:billing_contact)

      assert_performed_audit_entries(count: 1, only: "billing.contact_delete") do
        contact.destroy!
      end
    end
  end
end
