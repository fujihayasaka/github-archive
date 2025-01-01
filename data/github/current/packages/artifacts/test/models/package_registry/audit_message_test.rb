# typed: true
# frozen_string_literal: true

require "test_helper"

module PackageRegistry
  class AuditMessageTest < GitHub::TestCase

    def get_message(actor_id: 2, actor: "monalisa", org_id: 1, org: "github", repo_id: 3, repo: "packages-test",
                    package_id: 7, package: "alpine", ecosystem: "DOCKER", version_id: 10, version: "v1",
                    storage_bytes: 7777, is_republished: false, deleted_at_seconds: 1606547292, deleted_at_nanos: 0)

      message = Hydro::Consumer::ConsumerMessage.new(
        source_message: nil,
        schema: nil,
        timestamp: nil,
        id: nil,
        value: {
          actor: {
            id: actor_id,
            login: actor
          },
          package: {
            id: package_id,
            name: package,
            registry_type: ecosystem,
            repository: {
              id: repo_id,
              name: repo,
            },
            owner_org: {
              id: org_id,
              login: org
            }
          },
          version: {
            id: version_id,
            version: version
          },
          storage_bytes: storage_bytes,
          is_republished: is_republished,
          deleted_at: {
            seconds: deleted_at_seconds,
            nanos: deleted_at_nanos
          }
        }
      )

      expected_values = {
        actor_id: actor_id,
        actor: actor,
        org_id: org_id,
        org: org,
        repo_id: repo_id,
        repo: repo,
        package_id: package_id,
        package: package,
        ecosystem: ecosystem,
        version_id: version_id,
        version: version,
        storage_bytes: storage_bytes,
        is_republished: is_republished,
        deleted_at_seconds: deleted_at_seconds,
        deleted_at_nanos: deleted_at_nanos,
        deleted_time: Instrumentation.format_time(seconds: deleted_at_seconds, nanos: deleted_at_nanos)
      }

      [GitHub::StreamProcessors::Message.new(message), expected_values]
    end

    test "all fields are set correctly" do

      message, expected_values = get_message

      audit_message = AuditMessage.new(message) do |msg|
        msg.actor_id = msg.get(:actor, :id)
        msg.actor = msg.get(:actor, :login)
        msg.org_id = msg.get(:package, :owner_org, :id)
        msg.org = msg.get(:package, :owner_org, :login)
        msg.repo_id = msg.get(:package, :repository, :id)
        msg.repo = msg.get(:package, :repository, :name)
        msg.package_id = msg.get(:package, :id)
        msg.package = msg.get(:package, :name)
        msg.ecosystem = msg.get(:package, :registry_type)
        msg.version_id = msg.get(:version, :id)
        msg.version = msg.get(:version, :version)
        msg.storage_bytes = msg.get(:storage_bytes)
        msg.is_republished = msg.get(:is_republished)
        msg.deleted_at_seconds = msg.get(:deleted_at, :seconds)
        msg.deleted_at_nanos = msg.get(:deleted_at, :nanos)
      end

      assert_equal(false, audit_message.skipped?)
      assert_equal(expected_values[:actor_id], audit_message.actor_id)
      assert_equal(expected_values[:actor], audit_message.actor)
      assert_equal(expected_values[:org_id], audit_message.org_id)
      assert_equal(expected_values[:org], audit_message.org)
      assert_equal(expected_values[:repo_id], audit_message.repo_id)
      assert_equal(expected_values[:repo], audit_message.repo)
      assert_equal(expected_values[:package_id], audit_message.package_id)
      assert_equal(expected_values[:package], audit_message.package)
      assert_equal(expected_values[:ecosystem], audit_message.ecosystem)
      assert_equal(expected_values[:version_id], audit_message.version_id)
      assert_equal(expected_values[:version], audit_message.version)
      assert_equal(expected_values[:storage_bytes], audit_message.storage_bytes)
      assert_equal(expected_values[:is_republished], audit_message.is_republished)
      assert_equal(expected_values[:deleted_at_seconds], audit_message.deleted_at_seconds)
      assert_equal(expected_values[:deleted_at_nanos], audit_message.deleted_at_nanos)
      assert_equal(expected_values[:deleted_time], audit_message.deleted_time)
    end

    test "message is skipped when key is missing" do

      message, _ = get_message

      audit_message = AuditMessage.new(message) do |msg|
        msg.actor_id = msg.get(:actor, :identifier)
      end

      assert(audit_message.skipped?)
    end

    test "message is not skipped when key is missing and skip_if_missing is false" do

      message, _ = get_message

      audit_message = AuditMessage.new(message) do |msg|
        msg.actor_id = msg.get(:actor, :identifier, skip_if_missing: false)
      end

      assert_equal(false, audit_message.skipped?)
    end

    test "docker_base_layer returns true when ecosystem is docker and version is docker-base-layer" do

      message, _ = get_message(version: "docker-base-layer")

      audit_message = AuditMessage.new(message) do |msg|
        msg.actor_id = msg.get(:actor, :identifier)
      end

      assert(audit_message.skipped?)
    end

    test "message is skipped when version is docker-base-layer" do

      message, _ = get_message(version: "docker-base-layer")

      audit_message = AuditMessage.new(message) do |msg|
        msg.ecosystem = msg.get(:package, :registry_type)
        msg.version = msg.get(:version, :version)
      end

      assert(audit_message.skipped?)
    end

  end
end
