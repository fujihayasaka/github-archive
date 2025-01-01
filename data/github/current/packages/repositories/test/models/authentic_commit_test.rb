# typed: true
# frozen_string_literal: true

require "test_helper"

class AuthenticCommitsTest < GitHub::TestCase
  context "#bulk_insert" do
    test "inserts only new commits" do
      # SHA and network ID are random/arbitrary
      existing_network_id = 5
      existing_oid = "a" * 40
      create(:authentic_commit, network_id: existing_network_id, oid: existing_oid)

      assert_equal 1, AuthenticCommit.count

      new_network_id = existing_network_id + 1
      new_oid = "b" * 40
      new_verified_at = Time.new(2024, 4, 4)

      to_insert = [
        {
          network_id: existing_network_id,
          oid: existing_oid,
          verified_at: Time.new(2022, 1, 5),
        },
        {
          network_id: new_network_id,
          oid: new_oid,
          verified_at: Time.new(2024, 4, 4),
        }
      ]

      assert_max_query_count(1) do
        AuthenticCommit.bulk_insert(to_insert)
      end

      assert_equal 2, AuthenticCommit.count

      commit = AuthenticCommit.find_by(oid: new_oid)
      refute_nil commit
      assert_equal new_network_id, commit&.network_id
      assert_equal new_oid, commit&.oid
      assert_equal new_verified_at, commit&.verified_at
    end

    test "sorts commits by network_id and oid before inserting" do
      network_ids = [1, 2, 3]
      oids = ["a" * 40, "b" * 40, "c" * 40]

      verified_at = Time.new(2024, 4, 4)

      sorted = []
      3.times do |x|
        3.times do |y|
          sorted << { network_id: network_ids[x], oid: oids[y], verified_at: }
        end
      end

      AuthenticCommit.expects(:upsert_all).with { |val| val == sorted }

      to_insert = [
        { network_id: network_ids[1], oid: oids[2], verified_at:, },
        { network_id: network_ids[0], oid: oids[1], verified_at:, },
        { network_id: network_ids[2], oid: oids[0], verified_at:, },
        { network_id: network_ids[2], oid: oids[1], verified_at:, },
        { network_id: network_ids[0], oid: oids[0], verified_at:, },
        { network_id: network_ids[1], oid: oids[0], verified_at:, },
        { network_id: network_ids[2], oid: oids[2], verified_at:, },
        { network_id: network_ids[0], oid: oids[2], verified_at:, },
        { network_id: network_ids[1], oid: oids[1], verified_at:, },
      ]

      AuthenticCommit.bulk_insert(to_insert)
    end
  end
end
