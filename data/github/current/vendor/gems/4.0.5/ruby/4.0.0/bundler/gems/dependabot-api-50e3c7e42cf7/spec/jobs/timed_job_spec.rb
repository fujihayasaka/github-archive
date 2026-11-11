# typed: strict
# frozen_string_literal: true

require "rails_helper"

class TestTimedJob < TimedJob
  extend T::Sig
  IdMock = Struct.new(:id)

  sig do
    override.
      params(args: T.untyped, offset_id: Integer, kwargs: T.untyped).
      returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def fetch_batch(*args, offset_id:, **kwargs)
    return [] if offset_id >= 6

    Array.new(3).map do
      offset_id += 1
      IdMock.new(id: offset_id)
    end
  end

  sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
  def process_item(*args, item:, **kwargs); end

  sig { override.params(args: T.untyped, is_last_job: T::Boolean, num_processed_items: Integer, kwargs: T.untyped).void }
  def post_process(*args, is_last_job:, num_processed_items:, **kwargs); end

  sig { override.params(args: T.untyped, kwargs: T.untyped).void }
  def finalize_sequence(*args, **kwargs); end
end

RSpec.describe TimedJob do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:sequence_id) { SecureRandom.uuid }
  let(:timeout_sec) { nil } # use the default timeout_sec from TimedJob
  let(:job) { TestTimedJob.new(sequence_id:, timeout_sec:) }

  it "processes multiple batches" do
    allow(job).to receive(:fetch_batch).and_call_original

    job.perform_now
    expect(job).to have_received(:fetch_batch).with(
      hash_including(offset_id: 0, sequence_id: sequence_id)
    ).once
    expect(job).to have_received(:fetch_batch).with(
      hash_including(offset_id: 3, sequence_id: sequence_id)
    ).once
  end

  it "processes each item" do
    allow(job).to receive(:process_item)

    job.perform_now
    expect(job).to have_received(:process_item).with(
      hash_including(sequence_id: sequence_id)
    ).exactly(6).times
  end

  it "does post-processing" do
    allow(job).to receive(:post_process)

    job.perform_now
    expect(job).to have_received(:post_process).with(
      hash_including(
        is_last_job: true,
        num_processed_items: 6,
        sequence_id: sequence_id,
        num_in_sequence: 1
      )
    ).once
  end

  it "finalizes the sequence" do
    allow(job).to receive(:finalize_sequence)

    job.perform_now
    expect(job).to have_received(:finalize_sequence).with(
      hash_including(
        sequence_id: sequence_id,
        num_in_sequence: 1
      )
    ).once
  end

  describe "when the timeout is reached" do
    let(:timeout_sec) { 0.0 }

    it "enqueues a new job" do
      freeze_time do
        expect { job.perform_now }.to have_enqueued_job(TestTimedJob).with(
          hash_including(
            initial_start: Time.current.utc,
            offset_id: 1,
            num_in_sequence: 2,
            sequence_id: sequence_id,
          )
        )
      end
    end

    it "calls finalize_sequence in the last job only" do
      allow(job).to receive(:finalize_sequence)

      # keep executing the same job instance, to maintain stubbed
      # state across invocations
      allow(job).to receive(:enqueue_next_job) do |*args, **kwargs|
        job.perform(*args, **kwargs)
      end

      # 6 jobs to process 1 item each before timer.expired? returns true
      # and a 7th job to find no remaining items and finalize the sequence
      expected_job_count = 7

      job.perform_now
      expect(job).to have_received(:finalize_sequence).with(
        hash_including(
          sequence_id: sequence_id,
          num_in_sequence: expected_job_count,
          sequence_num_processed_items: 6,
        )
      ).once
    end
  end
end
