# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseAttestationTest < GitHub::TestCase
  fixtures do
    @user1 = create(:user)
    @user2 = create(:user)
    @user3 = create(:user)
  end

  setup do
    # conditionally enables feature flag in Enterprise mode only.
    GitHub.stubs(restrict_contractors_from_default_access_to_internal_repos?: GitHub.enterprise?)
  end

  context ".contractor?" do
    test "returns false when no attestation exists for a user", enterprise_only: true do
      refute EnterpriseAttestation.contractor?(@user1)
    end

    test "returns true for user with contractor attestation", enterprise_only: true  do
      EnterpriseAttestation.set(@user1.id, contractor: true)
      assert EnterpriseAttestation.contractor?(@user1)
    end

    test "returns false without feature flag", enterprise_only: true do
      GitHub.stubs(restrict_contractors_from_default_access_to_internal_repos?: false)
      EnterpriseAttestation.set(@user1.id, contractor: true)
      refute EnterpriseAttestation.contractor?(@user1)
    end

    test "returns false when not in Enterprise", skip_enterprise: true do
      EnterpriseAttestation.set(@user1.id, contractor: true)
      refute EnterpriseAttestation.contractor?(@user1)
    end
  end

  context ".contractor_ids" do
    test "returns list contractor User IDs", enterprise_only: true do
      assert_equal [], EnterpriseAttestation.contractor_ids

      EnterpriseAttestation.set(@user1.id, contractor: true)
      assert_equal [@user1.id], EnterpriseAttestation.contractor_ids

      EnterpriseAttestation.set(@user2.id, contractor: true)
      assert_equal [@user1.id, @user2.id], EnterpriseAttestation.contractor_ids
    end

    test "returns an empty list without feature flag", enterprise_only: true do
      GitHub.stubs(restrict_contractors_from_default_access_to_internal_repos?: false)
      assert_equal [], EnterpriseAttestation.contractor_ids

      EnterpriseAttestation.set(@user1.id, contractor: true)
      assert_equal [], EnterpriseAttestation.contractor_ids
    end

    test "returns a single list even if we have to split internally", enterprise_only: true do
      EnterpriseAttestation::Storage.stub_const(:CONTRACTORS_INDEX_SPLIT_SIZE, 5) do
        1.upto(30) do |id|
          EnterpriseAttestation.set(id, contractor: true)
        end
        assert_equal (1..30).to_a, EnterpriseAttestation.contractor_ids
      end
    end

    test "works after upgrading from earlier versions (which did not split long lists internally)", enterprise_only: true do
      EnterpriseAttestation::Storage.stub_const(:CONTRACTORS_INDEX_SPLIT_SIZE, 5) do
        # Data from previous version
        GitHub.kv.set("ent:attest:contractors", (1..10).to_a.to_json) # rubocop:todo GitHub/DoNotUseGlobalKv
        1.upto(10) do |id|
          GitHub.kv.set("ent:attest:contractor:#{id}", (Time.now.to_i).to_json) # rubocop:todo GitHub/DoNotUseGlobalKv
        end

        assert_equal (1..10).to_a, EnterpriseAttestation.contractor_ids
      end
    end

    test "returns an empty list when not in Enterprise", skip_enterprise: true do
      assert_equal [], EnterpriseAttestation.contractor_ids

      EnterpriseAttestation.set(@user1.id, contractor: true)
      assert_equal [], EnterpriseAttestation.contractor_ids
    end

    test "paginates", enterprise_only: true do
      user1 = create(:user, login: "user-a")
      user2 = create(:user, login: "user-b")
      user3 = create(:user, login: "user-c")
      user4 = create(:user, login: "user-d")
      user5 = create(:user, login: "user-e")

      EnterpriseAttestation.set(user1.id, contractor: true)
      EnterpriseAttestation.set(user2.id, contractor: true)
      EnterpriseAttestation.set(user3.id, contractor: true)
      EnterpriseAttestation.set(user4.id, contractor: true)
      EnterpriseAttestation.set(user5.id, contractor: true)

      contractors = EnterpriseAttestation.contractor_ids(page: 1, per_page: 2)
      assert_equal 2, contractors.count
      assert_same_elements [user1.id, user2.id], contractors

      contractors = EnterpriseAttestation.contractor_ids(page: 2, per_page: 2)
      assert_equal 2, contractors.count
      assert_same_elements [user3.id, user4.id], contractors

      contractors = EnterpriseAttestation.contractor_ids(page: 3, per_page: 2)
      assert_equal 1, contractors.count
      assert_same_elements [user5.id], contractors
    end
  end

  context ".set" do
    test "attests user is a contractor when set true", enterprise_only: true do
      EnterpriseAttestation.set(@user1.id, contractor: true)
      assert EnterpriseAttestation.contractor?(@user1.id)
    end

    test "attests user is not a contractor when set false", enterprise_only: true do
      EnterpriseAttestation.set(@user1.id, contractor: true)
      assert EnterpriseAttestation.contractor?(@user1.id)

      EnterpriseAttestation.set(@user1.id, contractor: false)
      refute EnterpriseAttestation.contractor?(@user1.id)
    end

    test "adds user to index when set true", enterprise_only: true do
      assert_equal [], EnterpriseAttestation.contractor_ids
      EnterpriseAttestation.set(@user1.id, contractor: true)
      assert_equal [@user1.id], EnterpriseAttestation.contractor_ids
    end

    test "removes user from index when set false", enterprise_only: true do
      EnterpriseAttestation.set(@user1.id, contractor: true)
      assert_equal [@user1.id], EnterpriseAttestation.contractor_ids

      EnterpriseAttestation.set(@user1.id, contractor: false)
      assert_equal [], EnterpriseAttestation.contractor_ids
    end

    test "raises an exception when adding above contractors limit", enterprise_only: true do
      EnterpriseAttestation::stub_const(:MAX_CONTRACTORS, 2) do
        EnterpriseAttestation.set(@user1.id, contractor: true)
        EnterpriseAttestation.set(@user2.id, contractor: true)
        assert_raises EnterpriseAttestation::ContractorsLimitExceeded do
          EnterpriseAttestation.set(@user3.id, contractor: true)
        end

        EnterpriseAttestation.set(@user2.id, contractor: false)
        assert_nothing_raised do
          EnterpriseAttestation.set(@user3.id, contractor: true)
        end
      end
    end

    test "splits index internally when we have too many contractors", enterprise_only: true do
      EnterpriseAttestation::Storage.stub_const(:CONTRACTORS_INDEX_SPLIT_SIZE, 5) do
        # Works for growth
        1.upto(12) do |id|
          EnterpriseAttestation.set(id, contractor: true)
        end
        assert_equal (1..12).to_a, EnterpriseAttestation.contractor_ids

        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal [1, 2, 3, 4, 5],  JSON.parse(GitHub.kv.get("ent:attest:contractors").value { nil })
        # rubocop:enable GitHub/DoNotUseGlobalKv
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal [6, 7, 8, 9, 10], JSON.parse(GitHub.kv.get("ent:attest:contractors:2").value { nil })
        # rubocop:enable GitHub/DoNotUseGlobalKv
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal [11, 12],         JSON.parse(GitHub.kv.get("ent:attest:contractors:3").value { nil })
        # rubocop:enable GitHub/DoNotUseGlobalKv
        assert_nil GitHub.kv.get("ent:attest:contractors:4").value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv

        # Works for shrinking
        (1..12).filter(&:odd?).map do |id|
          EnterpriseAttestation.set(id, contractor: false)
        end
        assert_equal [2, 4, 6, 8, 10, 12], EnterpriseAttestation.contractor_ids

        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal [2, 4, 6, 8, 10].to_a, JSON.parse(GitHub.kv.get("ent:attest:contractors").value { nil })
        # rubocop:enable GitHub/DoNotUseGlobalKv
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal [12],                  JSON.parse(GitHub.kv.get("ent:attest:contractors:2").value { nil })
        # rubocop:enable GitHub/DoNotUseGlobalKv
        assert_nil GitHub.kv.get("ent:attest:contractors:3").value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
      end
    end

    # See https://github.com/github/github/pull/173687
    test "works after upgrading the server from earlier versions (which did not split long lists internally)", enterprise_only: true do
      EnterpriseAttestation::Storage.stub_const(:CONTRACTORS_INDEX_SPLIT_SIZE, 5) do
        # Data from previous version
        GitHub.kv.set("ent:attest:contractors", (1..10).to_a.to_json) # rubocop:todo GitHub/DoNotUseGlobalKv
        1.upto(10) do |id|
          GitHub.kv.set("ent:attest:contractor:#{id}", (Time.now.to_i).to_json) # rubocop:todo GitHub/DoNotUseGlobalKv
        end

        EnterpriseAttestation.set(11, contractor: true)
        assert_equal (1..11).to_a, EnterpriseAttestation.contractor_ids

        EnterpriseAttestation.set(1, contractor: false)
        assert_equal (2..11).to_a, EnterpriseAttestation.contractor_ids
      end
    end

    test "does not set attestation when not in Enterprise", skip_enterprise: true do
      refute EnterpriseAttestation.set(@user1.id, contractor: true)
      assert_nil EnterpriseAttestation.get(@user1.id)
    end
  end

  context ".get" do
    test "returns attestation when user is attested as contractor", enterprise_only: true do
      EnterpriseAttestation.set(@user1.id, contractor: true)

      actual = EnterpriseAttestation.get(@user1.id)

      assert_equal @user1.id, actual.user_id
      assert actual.contractor
    end

    test "returns nil when user is not attested as contractor", enterprise_only: true do
      EnterpriseAttestation.set(@user1.id)
      assert_nil EnterpriseAttestation.get(@user1.id)
    end

    test "returns nil when not in Enterprise", skip_enterprise: true do
      # permit writing contractor attestation to prove `get` returns `nil`
      # even when data is available to return.
      GitHub.stubs(restrict_contractors_from_default_access_to_internal_repos?: true) do
        assert EnterpriseAttestation.set(@user1.id, contractor: true)
      end

      assert_nil EnterpriseAttestation.get(@user1.id)
    end
  end
end
