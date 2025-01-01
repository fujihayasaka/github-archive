# typed: true
# frozen_string_literal: true

require "test_helper"

class PushHydroMessageJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @repo = create(:repository, from_example: :simple)
  end

  setup do
    @message = {
      repository_id: @repo.id,
      ref_updates: [{ ref: "refs/heads/master", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }],
      pushed_at: Time.now,
      enabled_flags: [],
      pusher: @repo.owner_login
    }
  end

  class TestPushJob < Repositories::PushHydroMessageJob
    queue_as :test_push_job

    def perform
      nil
    end
  end

  test "skips wiki push by default" do
    @message[:path] = @repo.unsullied_wiki.shard_path
    TestPushJob.any_instance.expects(:perform).never
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "test_push_job")
  end

  test "performs for wiki when opted in" do
    TestPushJob.applies_to_wikis!
    @message[:path] = @repo.unsullied_wiki.shard_path

    TestPushJob.any_instance.expects(:perform).once
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "test_push_job")

    TestPushJob.applies_to_wikis = false # reset
  end

  test "discards when repo is deleted" do
    Repository.any_instance.stubs(:deleted?).returns(true)
    TestPushJob.any_instance.expects(:perform).never
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "test_push_job")
  end

  test "discards when repo is not on disk" do
    Repository.any_instance.stubs(:exists_on_disk?).returns(false)
    TestPushJob.any_instance.expects(:perform).never
    perform_hydro_message_job(@message, schema: "github.repositories.v1.Pushed", queue: "test_push_job")
  end

  test "discards when no ref updates by default" do
    TestPushJob.any_instance.expects(:perform).never
    perform_hydro_message_job(@message.merge({ ref_updates: [{ ref: "refs/heads/master", before: GitHub::NULL_OID, after: GitHub::NULL_OID }] }), schema: "github.repositories.v1.Pushed", queue: "test_push_job")
  end

  test "peforms for no ref updates when opted in" do
    TestPushJob.applies_to_empty_refs!
    TestPushJob.any_instance.expects(:perform).once
    perform_hydro_message_job(@message.merge({ ref_updates: [] }), schema: "github.repositories.v1.Pushed", queue: "test_push_job")
  end

  test "#large_push? returns true when ref updates exceed threshold" do
    updates = 1001.times.map { { ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) } }
    message = @message.merge({ ref_updates: updates, total_ref_count: 1001, ref_batch_number: 1 })
    encoded = GitHub.sync_hydro_publisher.encode(message, schema: "github.repositories.v1.Pushed", encoder: GitHub.hydro_encoder, timestamp: Time.now.to_f)
    job = TestPushJob.new(protobuf: encoded, headers: {}, schema: "github.repositories.v1.Pushed", timestamp: Time.now.to_f, timestamp_nano: 0, message: message, queue: "test_push_job")

    assert job.send(:large_push?)
  end

  test "sets up context based on message payload" do
    message = @message.merge(request_context: { request_id: SecureRandom.uuid, ip_address: "123.123.123.123"  })
    assert_nil GitHub.context[:request_id]

    # Test the context *within* the job perform, because other platform level code may setup/teardown context around perform
    class TestPushContextJob < Repositories::PushHydroMessageJob
      queue_as :test_push_context_job

      def perform
        raise "expected #{message[:request_context][:request_id]} to be in context" unless GitHub.context[:request_id] == message[:request_context][:request_id]
        raise "expected #{message[:request_context][:ip_address]} to be in context" unless GitHub.context[:actor_ip] == message[:request_context][:ip_address]
        raise "expected #{message[:pusher]} to be in context" unless GitHub.context[:actor_login] == message[:pusher]
        # make sure the context we push has the proper keys and values to be serialized later if necessary
        raise "could not serialize context" unless Hydro::EntitySerializer.request_context(GitHub.context.to_hash)
      end
    end

    assert_nothing_raised do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "test_push_job")
    end
  end

  test "logs based on message payload" do
    GitHub.flipper[:log_on_push_hydro_message_job].enable
    message = @message.merge(request_context: { request_id: SecureRandom.uuid, ip_address: "123.123.123.123"  })
    assert_nil GitHub.context[:request_id]

    expected_keys = {
      "Body" => "Performing PushHydroMessageJobTest::TestPushJob",
      "gh.repo.id" => @repo.id,
      "gh.request_id" => message[:request_context][:request_id],
      "gh.actor.name" => message[:pusher],
      "job" => "PushHydroMessageJobTest::TestPushJob",
      "gh.job.name" => "PushHydroMessageJobTest::TestPushJob",
    }

    assert_logged(**expected_keys) do
      perform_hydro_message_job(message, schema: "github.repositories.v1.Pushed", queue: "test_push_job")
    end
  end

  test "#ref_updates includes only branches and tags" do
    message = @message.merge({ ref_updates: [{ ref: "refs/heads/master", before: SecureRandom.hex(20), after: SecureRandom.hex(20) },
        { ref: "refs/heads/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) },
        { ref: "refs/tags/v1.0", before: SecureRandom.hex(20), after: SecureRandom.hex(20) },
        { ref: "refs/custom/foo", before: SecureRandom.hex(20), after: SecureRandom.hex(20) },
        { ref: "refs/random/bar", before: SecureRandom.hex(20), after: SecureRandom.hex(20) }]
    })

    encoded = GitHub.sync_hydro_publisher.encode(message, schema: "github.repositories.v1.Pushed", encoder: GitHub.hydro_encoder, timestamp: Time.now.to_f)
    job = TestPushJob.new(protobuf: encoded, headers: {}, schema: "github.repositories.v1.Pushed", timestamp: Time.now.to_f, timestamp_nano: 0, message: message, queue: "test_push_job")

    job_ref_updates = job.send(:ref_updates)

    assert_equal 3, job_ref_updates.count
    assert_same_elements job_ref_updates.map(&:ref), ["refs/heads/foo", "refs/heads/master", "refs/tags/v1.0"]
  end if GitHub.flipper[:branches_tags_only_push_jobs].enabled?

  test "processes up to 3 tags" do
    refs = T.let([
      { ref: "refs/heads/a", before: GitHub::NULL_OID, after: "1" * 40 }
    ], T.untyped)

    3.times do |i|
      refs << { ref: "refs/tags/#{i}", before: GitHub::NULL_OID, after: (i + 1).to_s * 40 }
    end

    message = @message.merge(ref_updates: refs)

    encoded = GitHub.sync_hydro_publisher.encode(message, schema: "github.repositories.v1.Pushed", encoder: GitHub.hydro_encoder, timestamp: Time.now.to_f)
    job = TestPushJob.new(protobuf: encoded, headers: {}, schema: "github.repositories.v1.Pushed", timestamp: Time.now.to_f, timestamp_nano: 0, message: message, queue: "test_push_job")

    job_ref_updates = job.send(:ref_updates)

    assert_equal 4, job_ref_updates.count
    assert_same_elements refs.map { |r| r[:ref] }, job_ref_updates.map(&:ref)
  end

  test "excludes tags if there are more than 3 tags" do
    refs = T.let([
      { ref: "refs/heads/a", before: GitHub::NULL_OID, after: "1" * 40 }
    ], T.untyped)

    4.times do |i|
      refs << { ref: "refs/tags/#{i}", before: GitHub::NULL_OID, after: (i + 1).to_s * 40 }
    end

    message = @message.merge(ref_updates: refs)

    encoded = GitHub.sync_hydro_publisher.encode(message, schema: "github.repositories.v1.Pushed", encoder: GitHub.hydro_encoder, timestamp: Time.now.to_f)
    job = TestPushJob.new(protobuf: encoded, headers: {}, schema: "github.repositories.v1.Pushed", timestamp: Time.now.to_f, timestamp_nano: 0, message: message, queue: "test_push_job")

    job_ref_updates = job.send(:ref_updates)

    assert_equal 1, job_ref_updates.count
  end
end
