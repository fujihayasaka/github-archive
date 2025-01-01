# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::KVTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)
    @repo = create(:public_repository, owner: @user)
    @keyname = "actions-kv-test-key"
  end

  context ".for_partition_key" do
    test "it doesn't raise any errors on wrapper creation" do
      assert_nothing_raised do
        Actions::KV.for_partition_key(@repo.id)
      end
    end

    test "it doesn't raise any errors on setting a value" do
      assert_nothing_raised do
        kv = Actions::KV.for_partition_key(@repo.id)
        kv.set(@keyname, "true")
      end
    end

    test "it doesn't raise any errors on setting a value with an expiry" do
      assert_nothing_raised do
        kv = Actions::KV.for_partition_key(@repo.id)
        kv.set(@keyname, "true", expires: (Date.today + 1).to_time)
      end
    end

    test "it can successfully read a value" do
      kv = Actions::KV.for_partition_key(@repo.id)
      kv.set(@keyname, "true")

      assert_equal true, kv.exists(@keyname).value { false }
    end

    test "it doesn't raise any errors on deleting a value" do
      kv = Actions::KV.for_partition_key(@repo.id)
      kv.set(@keyname, "true")

      assert_nothing_raised do
        kv.del(@keyname)
      end
    end
  end

  context ".for_key" do
    test "it doesn't raise any errors on wrapper creation" do
      assert_nothing_raised do
        Actions::KV.for_key(@keyname)
      end
    end

    test "it doesn't raise any errors on setting a value" do
      assert_nothing_raised do
        kv = Actions::KV.for_key(@keyname)
        kv.set(@keyname, "true")
      end
    end

    test "it doesn't raise any errors on setting a value with an expiry" do
      assert_nothing_raised do
        kv = Actions::KV.for_key(@keyname)
        kv.set(@keyname, "true", expires: (Date.today + 1).to_time)
      end
    end

    test "it can successfully read a value" do
      kv = Actions::KV.for_key(@keyname)
      kv.set(@keyname, "true")

      assert_equal true, kv.exists(@keyname).value { false }
    end

    test "it doesn't raise any errors on deleting a value" do
      kv = Actions::KV.for_key(@keyname)
      kv.set(@keyname, "true")

      assert_nothing_raised do
        kv.del(@keyname)
      end
    end
  end
end
