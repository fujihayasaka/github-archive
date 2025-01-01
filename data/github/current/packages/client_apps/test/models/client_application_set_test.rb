# typed: true
# frozen_string_literal: true

require "test_helper"

class ClientApplicationSetTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    reset_cache
  end

  context "#add" do
    test "records that the user has installed the given app" do
      set = ClientApplicationSet.new(@user.id)
      refute set.include?(:github_for_mac)
      assert set.add(:github_for_mac)
      assert set.include?(:github_for_mac)
    end

    test "raises an error when given an invalid application" do
      set = ClientApplicationSet.new(@user.id)
      assert_raises(ArgumentError) do
        set.add(:github_for_ibm_system_360)
      end
    end

    test "sets memcached key to prevent repeat invocations from writing to the database" do
      set = ClientApplicationSet.new(@user.id)
      with_cache_enabled do
        application = :github_for_mac
        application_id = ClientApplicationSet::APPLICATIONS[application]
        cache_key = "client_application_sets:#{@user.id}:#{application_id}"
        assert_nil GitHub.cache.get(cache_key)

        assert set.add(application)
        assert_equal true, GitHub.cache.get(cache_key), "Expected cache key to be present"
      end
    end

    test "does not attempt to write to the database if memcached key is set" do
      set = ClientApplicationSet.new(@user.id)
      with_cache_enabled do
        application = :github_for_mac
        application_id = ClientApplicationSet::APPLICATIONS[application]
        cache_key = "client_application_sets:#{@user.id}:#{application_id}"
        GitHub.cache.add(cache_key, true, 60)

        GitHub::SQL.any_instance.expects(:run).never
        refute set.add(application)
      end
    end

    test "is idemopotent" do
      set = ClientApplicationSet.new(@user.id)
      assert set.add(:github_for_mac)
      refute set.add(:github_for_mac)

      statement = <<-SQL
        SELECT COUNT(*) as `rows` FROM client_application_sets
        WHERE user_id = :user_id AND application_id = :application_id
      SQL
      application_id = ClientApplicationSet::APPLICATIONS[:github_for_mac]
      count = ApplicationRecord::Domain::Users.connection.select_value(Arel.sql(statement, user_id: @user.id, application_id: application_id))
      assert_equal 1, count
    end
  end

  context "#include?" do
    test "returns true when the user has an installation for the given app" do
      set = ClientApplicationSet.new(@user.id)
      set.add(:github_for_mac)
      assert set.include?(:github_for_mac)
    end

    test "returns false when the user does not have an installation for the given app" do
      set = ClientApplicationSet.new(@user.id)
      refute set.include?(:github_for_mac)
    end

    test "raises an error when given an invalid application" do
      set = ClientApplicationSet.new(@user.id)
      assert_raises(ArgumentError) do
        set.include?(:github_for_ibm_system_360)
      end
    end
  end

  context "#clear" do
    test "clears the user's set of installed applications" do
      set = ClientApplicationSet.new(@user.id)
      set.add(:github_for_mac)
      set.add(:github_for_windows)
      assert set.include?(:github_for_mac)
      assert set.include?(:github_for_windows)

      set.clear
      refute set.include?(:github_for_mac)
      refute set.include?(:github_for_windows)
    end
  end
end
