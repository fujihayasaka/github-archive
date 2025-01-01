# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsTradeScreeningRecordLinkTest < GitHub::TestCase
  setup do
    skip if GitHub.enterprise?
  end

  fixtures do
    @org_admin = create(:user)
    create(:account_screening_profile, owner: @org_admin)
    @org = create(:organization, admin: @org_admin)
  end

  context "#link_id" do
    test "returns link ID for the org" do
      @org_admin.link_trade_screening_record_to_org(organization: @org)
      assert_equal @org_admin.trade_screening_record.id, @org.trade_screening_record_link.link_id
    end
  end

  context "#update" do
    test "updates the link ID for an organization" do
      ref_id = @org.trade_screening_record_link.link_id
      assert_nil ref_id
      assert @org.trade_screening_record_link.update(id: @org_admin.trade_screening_record.id)

      ref_id = @org.trade_screening_record_link.link_id
      refute_nil ref_id
      assert_equal @org_admin.trade_screening_record.id, ref_id
    end
  end

  context "#remove" do
    test "removes the link ID for an organization" do
      @org.trade_screening_record_link.update(id: @org_admin.trade_screening_record.id)
      existing_ref_id = @org.trade_screening_record_link.link_id
      refute_nil existing_ref_id

      @org.trade_screening_record_link.remove
      ref_id = @org.trade_screening_record_link.link_id
      assert_nil ref_id
    end
  end
end
