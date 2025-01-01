# typed: true
# frozen_string_literal: true

require "test_helper"

class DummyAccessible < ActiveRecord::Base
  self.table_name = "dummy_accessibles"
  include StaffAccessible

  def event_prefix
    "accessible"
  end
end

class StaffAccessibleTest < GitHub::TestCase
  fixtures do
    @accessible = DummyAccessible.create
    @owner = create :user
  end

  setup_once do
    DummyAccessible.connection.create_table :dummy_accessibles
  end

  teardown_once do
    DummyAccessible.connection.drop_table :dummy_accessibles
  end

  context "associations" do
    test "has_many staff_access_grants" do
      assert_equal [], @accessible.staff_access_grants
    end

    test "has_many staff_access_requests" do
      assert_equal [], @accessible.staff_access_requests
    end
  end

  context "#active_staff_access_grant" do
    test "returns the most recent grant if it is active" do
      Timecop.freeze(1.day.ago) do
        create :staff_access_grant, accessible: @accessible, granted_by: @owner
      end

      new_grant = create :staff_access_grant, accessible: @accessible, granted_by: @owner

      assert_equal @accessible.active_staff_access_grant, new_grant
    end

    test "returns nil if the most recent grant is inactive" do
      Timecop.freeze(1.day.ago) do
        create :staff_access_grant, accessible: @accessible, granted_by: @owner
      end

      new_grant = create :staff_access_grant, accessible: @accessible, granted_by: @owner
      new_grant.update(revoked_at: Time.now)

      assert_nil @accessible.active_staff_access_grant
    end
  end

  context "#active_staff_access_request" do
    test "returns the most recent request" do
      Timecop.freeze(1.day.ago) do
        create :staff_access_request, accessible: @accessible
      end

      new_request = create :staff_access_request, accessible: @accessible

      assert_equal @accessible.latest_staff_access_request, new_request
    end

    test "returns nil if the most recent request is inactive" do
      Timecop.freeze(1.day.ago) do
        create :staff_access_request, accessible: @accessible
      end

      new_grant = create :staff_access_request, accessible: @accessible
      new_grant.update(cancelled_at: Time.now)

      assert_nil @accessible.active_staff_access_request
    end
  end
end
