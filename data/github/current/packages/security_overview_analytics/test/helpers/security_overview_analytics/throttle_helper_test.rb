# typed: true
# frozen_string_literal: true

require_relative "../../../../security_products/app/models/security_center/k_v"

require "test_helper"

module SecurityOverviewAnalytics
  class ThrottleHelperTest < GitHub::TestCase
    context ".throttle_kv_writes_with_fallback" do
      test "it calls the block" do
        kv_key = SecureRandom.uuid

        assert_changes(
          -> { SecurityCenter::KV.store.get(kv_key).value! },
          from: nil,
          to: 1.to_s
        ) do
          ThrottleHelper.throttle_kv_writes_with_fallback do
            SecurityCenter::KV.store.increment(kv_key)
          end
        end
      end

      context "when a throttler error is raised" do
        test "it calls the block" do
          kv_key = SecureRandom.uuid

          ApplicationRecord::Domain::KeyValues
            .stubs(:throttle_writes)
            .raises

          assert_changes(
            -> { SecurityCenter::KV.store.get(kv_key).value! },
            from: nil,
            to: 1.to_s
          ) do
            ThrottleHelper.throttle_kv_writes_with_fallback do
              SecurityCenter::KV.store.increment(kv_key)
            end
          end
        end
      end
    end
  end
end
