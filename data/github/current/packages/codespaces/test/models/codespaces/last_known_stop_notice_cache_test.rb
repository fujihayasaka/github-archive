# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::LastKnownStopNoticeCacheTest < GitHub::TestCase

  fixtures do
    @codespaces = create_list(:codespace, 2)
  end

  setup do
    @first_billable_owner_id = @codespaces.first.billable_owner_id
    @second_billable_owner_id = @codespaces.second.billable_owner_id
    @billable_owner_ids = @codespaces.map(&:billable_owner_id)
    GitHub.flipper[:codespaces_stop_notice_cache].enable
  end

  context "#mset" do
    test "does nothing when codespaces_stop_notice_cache feature is disabled" do
      GitHub.flipper[:codespaces_stop_notice_cache].disable
      Codespaces::Kv.store.expects(:mset).never

      Codespaces::LastKnownStopNoticeCache.mset(
        billable_owner_ids: ["owner_id_1"],
        notice: Codespaces::LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_ORG
      )
    end

    test "does not set any values if billable_owner_ids is nil" do
      GitHub::KV.any_instance.expects(:mset).never

      Codespaces::LastKnownStopNoticeCache.mset(
        billable_owner_ids: nil,
        notice: Codespaces::LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_ORG
      )
    end

    test "does not set any values if billable_owner_ids is empty" do
      GitHub::KV.any_instance.expects(:mset).never

      Codespaces::LastKnownStopNoticeCache.mset(
        billable_owner_ids: [],
        notice: Codespaces::LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_ORG
      )
    end

    test "does not set any values if notice is blank" do
      GitHub::KV.any_instance.expects(:mset).never

      Codespaces::LastKnownStopNoticeCache.mset(billable_owner_ids: @billable_owner_ids, notice: nil)
    end

    test "sets values when there are both billable owner ids and a notice present" do
      Codespaces::LastKnownStopNoticeCache.mset(billable_owner_ids: @billable_owner_ids, notice: "spending_limit_reached")

      assert_equal "spending_limit_reached", Codespaces::LastKnownStopNoticeCache.get(billable_owner_id: @first_billable_owner_id)
      assert_equal "spending_limit_reached", Codespaces::LastKnownStopNoticeCache.get(billable_owner_id: @second_billable_owner_id)
    end
  end

  context "#get" do
    test "does nothing when codespaces_stop_notice_cache feature is disabled" do
      GitHub.flipper[:codespaces_stop_notice_cache].disable
      Codespaces::Kv.store.expects(:get).never

      assert_nil Codespaces::LastKnownStopNoticeCache.get(billable_owner_id: "owner_id_1")
    end

    test "returns stored value when present" do
      expected_value = Codespaces::LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_ORG
      Codespaces::LastKnownStopNoticeCache.mset(billable_owner_ids: [@first_billable_owner_id], notice: expected_value)

      assert_equal expected_value, Codespaces::LastKnownStopNoticeCache.get(billable_owner_id: @first_billable_owner_id)
    end

    test "returns nil for keys that are not set" do
      assert_nil Codespaces::LastKnownStopNoticeCache.get(billable_owner_id: @first_billable_owner_id)
    end
  end

  context "#get_text" do
    test "returns nil when codespaces_stop_notice_cache feature is disabled" do
      GitHub.flipper[:codespaces_stop_notice_cache].disable
      Codespaces::Kv.store.expects(:get).never

      assert_nil Codespaces::LastKnownStopNoticeCache.get_text(billable_owner_id: "owner_id_1")
    end

    test "returns nil when cached value is not present for billable_owner" do
      billable_owner_id = "owner_id_1"

      assert_nil Codespaces::LastKnownStopNoticeCache.get_text(billable_owner_id: billable_owner_id)
    end

    test "returns text when cached value is present for billable_owner" do
      billable_owner_id = "owner_id_1"
      Codespaces::LastKnownStopNoticeCache.mset(
        billable_owner_ids: [billable_owner_id],
        notice: Codespaces::LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_USER
      )

      assert_equal(
        "you've used 100% of your spending limit for GitHub Codespaces. You can update your limit in your GitHub billing settings to continue using Codespaces.",
        Codespaces::LastKnownStopNoticeCache.get_text(billable_owner_id: billable_owner_id)
      )
    end
  end

  context "#key" do
    test "it returns a key for a given billable_owner_id" do
      billable_owner_id = "123"

      assert_equal "codespaces:last_known_stop_notice:v1:123", Codespaces::LastKnownStopNoticeCache.key(billable_owner_id: billable_owner_id)
    end
  end

  context "#clear" do
    test "does nothing when last_known_stop_notice doesn't exist" do
      billable_owner_id = "owner_id_1"
      Codespaces::Kv.store.expects(:del).never

      Codespaces::LastKnownStopNoticeCache.clear(billable_owner_id: billable_owner_id)
    end

    test "clears last_known_stop_notice when it exists for a given billable owner" do
      billable_owner_id = "owner_id_1"
      Codespaces::LastKnownStopNoticeCache.mset(
        billable_owner_ids: [billable_owner_id],
        notice: Codespaces::LastKnownStopNoticeCache::SPENDING_LIMIT_REACHED_FOR_ORG
      )

      Codespaces::LastKnownStopNoticeCache.clear(billable_owner_id: billable_owner_id)
      assert_nil Codespaces::LastKnownStopNoticeCache.get(billable_owner_id: billable_owner_id)
    end
  end
end
