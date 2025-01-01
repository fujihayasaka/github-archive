# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ContactLinkTest < GitHub::TestCase
  setup do
    skip unless GitHub.billing_enabled?
    enable_feature_flag(:read_billing_information_from_contacts)
  end

  fixtures do
    @org_admin = create(:credit_card_user)
    @contact = create(:billing_contact, customer: @org_admin.customer)
    @org = create(:organization, admin: @org_admin)
  end

  context "#link_id" do
    test "returns link ID for the org" do
      @org.billing_contact_link.update(id: @contact.id)
      assert_equal @org_admin.billing_contact.id, @org.billing_contact_link.link_id
    end

    test "returns nil if there is no linked ID" do
      assert_nil @org.billing_contact_link.link_id
    end
  end

  context "#update" do
    test "updates the link ID for an organization" do
      ref_id = @org.billing_contact_link.link_id
      assert_nil ref_id
      assert @org.billing_contact_link.update(id: @org_admin.billing_contact.id)

      ref_id = @org.billing_contact_link.link_id
      refute_nil ref_id
      assert_equal @org_admin.billing_contact.id, ref_id
    end

    test "doesn't update the link ID for an organization when the link id doesn't change" do
      assert @org.billing_contact_link.update(id: @org_admin.billing_contact.id)
      ref_id = @org.billing_contact_link.link_id
      refute_nil ref_id
      assert_equal @org_admin.billing_contact.id, ref_id

      _, queries = log_queries do
        assert @org.billing_contact_link.update(id: @org_admin.billing_contact.id)
      end
      update_queries = queries.map(&:digested_sql).select { |q|  q.start_with?("INSERT ", "UPDATE ") }

      assert_equal 0, update_queries.count
    end
  end

  context "#remove" do
    test "removes the link ID for an organization" do
      @org.billing_contact_link.update(id: @org_admin.billing_contact.id)
      existing_ref_id = @org.billing_contact_link.link_id
      refute_nil existing_ref_id

      @org.billing_contact_link.remove
      ref_id = @org.billing_contact_link.link_id
      assert_nil ref_id
    end

    test "doesn't fail to remove non-existant link ID for an organization" do
      ref_id = @org.billing_contact_link.link_id
      assert_nil ref_id

      @org.billing_contact_link.remove
      ref_id = @org.billing_contact_link.link_id
      assert_nil ref_id
    end
  end
end
