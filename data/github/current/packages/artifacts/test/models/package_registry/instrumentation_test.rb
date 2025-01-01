# typed: true
# frozen_string_literal: true
require "test_helper"

module PackageRegistry
  class PackageEventsTest < GitHub::TestCase
    test "instruments package deleted" do

      meta = {
        actor_id: 7,
        actor: "mona",
        org_id: 777,
        org: "packages",
        package_id: 1,
        package: "alpine",
        ecosystem: "docker",
        deleted_time: "2020-12-03 16:10:51 -0600",
      }

      events = subscribe "packages.package_deleted"

      Instrumentation.package_deleted(
        actor_id: meta[:actor_id],
        actor: meta[:actor],
        org_id: meta[:org_id],
        org: meta[:org],
        package_id: meta[:package_id],
        package: meta[:package],
        ecosystem: meta[:ecosystem],
        deleted_time: meta[:deleted_time]
      )

      assert event = events.pop, "an event was expected"
      assert_equal meta, event.payload
    end

    test "instruments package published" do
      meta = {
        actor_id: 7,
        actor: "mona",
        org_id: 777,
        org: "packages",
        package_id: 1,
        package: "alpine",
        ecosystem: "docker",
        is_republished: false,
        published_time: "2020-12-03 16:10:51 -0600",
      }

      events = subscribe "packages.package_published"

      Instrumentation.package_published(
        actor_id: meta[:actor_id],
        actor: meta[:actor],
        org_id: meta[:org_id],
        org: meta[:org],
        package_id: meta[:package_id],
        package: meta[:package],
        ecosystem: meta[:ecosystem],
        is_republished: meta[:is_republished],
        published_time: meta[:published_time],
      )

      assert event = events.pop, "an event was expected"
      assert_equal meta, event.payload
    end

    test "instruments package version deleted" do

      meta = {
        actor_id: 7,
        actor: "mona",
        org_id: 777,
        org: "packages",
        package_id: 1,
        package: "alpine",
        ecosystem: "docker",
        version_id: 3,
        version: "v1",
        deleted_time: "2020-12-03 16:10:51 -0600",
      }

      events = subscribe "packages.package_version_deleted"

      Instrumentation.package_version_deleted(
        actor_id: meta[:actor_id],
        actor: meta[:actor],
        org_id: meta[:org_id],
        org: meta[:org],
        package_id: meta[:package_id],
        package: meta[:package],
        ecosystem: meta[:ecosystem],
        version_id: meta[:version_id],
        version: meta[:version],
        deleted_time: meta[:deleted_time]
      )

      assert event = events.pop, "an event was expected"
      assert_equal meta, event.payload
    end

    test "instruments package version published" do
      meta = {
        actor_id: 7,
        actor: "mona",
        org_id: 777,
        org: "packages",
        package_id: 1,
        package: "alpine",
        ecosystem: "docker",
        version_id: 3,
        version: "v1",
        is_republished: false,
        storage_bytes: 123,
        published_time: "2020-12-03 16:10:51 -0600",
      }

      events = subscribe "packages.package_version_published"

      Instrumentation.package_version_published(
        actor_id: meta[:actor_id],
        actor: meta[:actor],
        org_id: meta[:org_id],
        org: meta[:org],
        package_id: meta[:package_id],
        package: meta[:package],
        ecosystem: meta[:ecosystem],
        version_id: meta[:version_id],
        version: meta[:version],
        republished: meta[:is_republished],
        storage_bytes: meta[:storage_bytes],
        published_time: meta[:published_time],
      )

      assert event = events.pop, "an event was expected"
      assert_equal meta, event.payload
    end
  end
end
