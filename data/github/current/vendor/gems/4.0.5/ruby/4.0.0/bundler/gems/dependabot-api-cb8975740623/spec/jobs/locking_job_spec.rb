# frozen_string_literal: true

require "rails_helper"

RSpec.describe LockingJob do
  include ActiveJob::TestHelper
  include LockingJobHelpers

  before do
    stub_const(
      "BasicLockedJob",
      Class.new(ApplicationJob) do
        include LockingJob
        locked_by timeout: 1.minute, key: LockingJob::DEFAULT_LOCK_PROC
        def perform(args)
          Dependabot::Logger.info(args)
        end
      end
    )
    stub_const(
      "CustomLockedJob",
      Class.new(ApplicationJob) do
        include LockingJob
        locked_by timeout: 1.minute, key: lambda { |job|
          job.arguments.first[:key]
        }
        def perform(key:); end
      end
    )
  end

  after do
    clear_job_locks(BasicLockedJob, CustomLockedJob)
  end

  it "does not attempt to obtain locks if the job returns a nil lock key" do
    job = BasicLockedJob.new(key: "key")
    allow(job).to receive(:lock_key).and_return(nil)
    expect(Restraint).not_to receive(:obtain_lock)
    job.perform_now
  end

  it "does not enqueue more than one job with the same lock key" do
    expect do
      BasicLockedJob.perform_later(key: "key")
      BasicLockedJob.perform_later(key: "key")
    end.to change(enqueued_jobs, :size).by(1)
  end

  it "enqueues multiple jobs with different lock keys" do
    expect do
      BasicLockedJob.perform_later(key: "key1")
      BasicLockedJob.perform_later(key: "key2")
    end.to change(enqueued_jobs, :size).by(2)
  end

  it "enqueues a job while the previously enqueued job is running" do
    allow(Restraint).to receive(:obtain_lock).and_call_original
    allow(Dependabot::Logger).to receive(:info).and_wrap_original do |original_method, *args|
      BasicLockedJob.perform_later("key")
      original_method.call(*args)
    end
    BasicLockedJob.perform_later("key")
    perform_enqueued_jobs

    expect(Restraint).to have_received(:obtain_lock).with(
      "enqueue:BasicLockedJob:#{Digest::SHA256.hexdigest('key')}", 1, 60, anything
    ).twice

    expect(Restraint).to have_received(:obtain_lock).with(
      "BasicLockedJob:#{Digest::SHA256.hexdigest('key')}", 1, 60, anything
    ).once
  end

  it "retries a job when the perform lock is already held" do
    job = BasicLockedJob.new("key")
    Restraint.lock!(job.lock_key, 1, job.class.lock_timeout) do
      expect do
        job.perform_now
      end.to have_enqueued_job(BasicLockedJob).with("key")
    end
  end

  it "retries a job when a recoverable redis error occurs before performing the job" do
    job = BasicLockedJob.new("key")
    allow(Restraint).to receive(:lock!).and_raise(Redis::CannotConnectError)
    expect do
      job.perform_now
    end.to have_enqueued_job(BasicLockedJob).with("key")
  end

  it "does not enqueue more than one job with the same lock key and set:wait" do
    expect do
      BasicLockedJob.set(wait: 10.seconds).perform_later(key: "key")
      BasicLockedJob.set(wait: 10.seconds).perform_later(key: "key")
    end.to change(enqueued_jobs, :size).by(1)
  end

  it "serializes and deserializes the lock key and enqueue mutex correctly" do
    job = BasicLockedJob.new(key: "key")
    job.enqueue_mutex = Restraint::Lock.new(
      key: "enqueue_mutex_key", count: 1, expires_at: 30.seconds.from_now, value: "1"
    )

    # The Aqueduct rails queue adapter used in production serializes the job to JSON
    # during enqueue and deserializes it back before performing.
    # We need to do the same in this test to verify that the lock data is correctly preserved through the serialization
    # process.
    # This test is explicitly needed because the ActiveJob::TestAdapter does not perform JSON serialization
    # of non-argument job payload, and will not preserve the enqueue mutex data without explicit serialization.
    serialized_job = JSON.generate(job.serialize)
    deserialized_job = BasicLockedJob.new.tap do |new_job|
      new_job.deserialize(JSON.parse(serialized_job))
    end

    expect(deserialized_job.lock_key).to eq(job.lock_key)
    expect(deserialized_job.enqueue_mutex).to be_a(Restraint::Lock)
    expect(deserialized_job.enqueue_mutex.key).to eq(job.enqueue_mutex.key)
    expect(deserialized_job.enqueue_mutex.count).to eq(job.enqueue_mutex.count)
    expect(deserialized_job.enqueue_mutex.expires_at.to_i).to eq(job.enqueue_mutex.expires_at.to_i)
    expect(deserialized_job.enqueue_mutex.value).to eq(job.enqueue_mutex.value)
  end

  context "using the default lock key proc" do
    it "stringifies hash arguments in the lock key" do
      job = BasicLockedJob.new(key1: "key1", key2: %w(key2a key2b), key3: nil)
      expect(job.lock_key).to eq("#{job.class.name}:#{Digest::SHA256.hexdigest('{key1:key1,key2:[key2a,key2b],key3:}')}")
    end

    it "stringifies array arguments in the lock key" do
      job = BasicLockedJob.new(key: %w(key1 key2))
      expect(job.lock_key).to eq("#{job.class.name}:#{Digest::SHA256.hexdigest('{key:[key1,key2]}')}")
    end

    it "stringifies nil arguments in the lock key" do
      job = BasicLockedJob.new(key: nil)
      expect(job.lock_key).to eq("#{job.class.name}:#{Digest::SHA256.hexdigest('{key:}')}")
    end

    it "stringifies multiple arguments in the lock key" do
      job = BasicLockedJob.new("key", key: "key1")
      expect(job.lock_key).to eq("#{job.class.name}:#{Digest::SHA256.hexdigest('key {key:key1}')}")
    end
  end

  context "using a custom lock key proc" do
    it "uses the custom lock key proc to generate the lock key" do
      job = CustomLockedJob.new(key: "my_custom_key")
      expect(job.lock_key).to eq("#{job.class.name}:#{Digest::SHA256.hexdigest('my_custom_key')}")
    end
  end
end
