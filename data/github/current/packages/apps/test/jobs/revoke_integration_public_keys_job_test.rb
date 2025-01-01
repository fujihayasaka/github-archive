# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RevokeIntegrationPublicKeysJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @repository = create(:repository, :minimal)

    @integration = create(:integration, default_permissions: { "metadata" => :read, "administration" => :write })
    installation = make_integration_installation(integration: @integration, repository: @repository)

    @bot = installation.bot
  end

  test "destroys public keys made by the app" do
    Timecop.freeze do
      now = Time.now.to_i

      key = @repository.public_keys.create_with_verification(verifier: @bot, key: Sham.ssh_public_key)
      assert_predicate key, :verified?

      RevokeIntegrationPublicKeysJob.perform_now(@integration, now)
      assert_nil PublicKey.find_by(id: key.id)
    end
  end

  test "instruments with 'removed by staff' explanation" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    Timecop.freeze do
      events = subscribe "public_key.delete"
      now = Time.now.to_i

      key = @repository.public_keys.create_with_verification(verifier: @bot, key: Sham.ssh_public_key)
      assert_predicate key, :verified?

      RevokeIntegrationPublicKeysJob.perform_now(@integration, now)

      expected_payload = {
        public_key_id: key.id,
        title: key.title,
        key: key.key,
        fingerprint: key.fingerprint,
        created_by: "user",
        read_only: "false",
        explanation: :removed_by_staff,
        incident: nil,
        repo: @repository.nwo,
        repo_id: @repository.id,
        public_repo: @repository.public?,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "public_key.delete", event.name
      assert_equal expected_payload, event.payload

      refute_empty GitHub.dogstats.increments("public_key", tags: ["action:destroy", "explanation:removed-by-staff"])
    end
  end

  test "does not destroy public keys made by an app verified by a user" do
    Timecop.freeze do
      now = Time.now.to_i

      key = @repository.public_keys.create_with_verification(verifier: @repository.owner, key: Sham.ssh_public_key)
      assert_predicate key, :verified?

      RevokeIntegrationPublicKeysJob.perform_now(@integration, now)
      refute_nil PublicKey.find_by(id: key.id)
    end
  end

  test "does not destroy public keys made after the given time" do
    Timecop.freeze do
      now = Time.now.to_i

      key = @repository.public_keys.create_with_verification(verifier: @bot, key: Sham.ssh_public_key)
      assert_predicate key, :verified?

      key.update(created_at: 2.days.from_now); key.reload

      RevokeIntegrationPublicKeysJob.perform_now(@integration, now)
      refute_nil PublicKey.find_by(id: key.id)
    end
  end

  test "retry conditions" do
    Timecop.freeze do
      assert_retry_on_dirty_exit job: RevokeIntegrationPublicKeysJob, args: [@bot, Time.now.to_i]
      assert_retry_on_throttler_error job: RevokeIntegrationPublicKeysJob, args: [@bot, Time.now.to_i]
    end
  end
end
