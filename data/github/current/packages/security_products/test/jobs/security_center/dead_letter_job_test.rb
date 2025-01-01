# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require_relative "../../../app/models/security_center/k_v"

module SecurityCenter
  class DeadLetterJob::CacheDataTest < GitHub::TestCase
    class NonApplicationJobTestClass; end

    fixtures do
      @target_job_type = ::SecurityCenter::RepositorySyncJob
      @target_job_inputs = { repository_id: 1, source_event: "sample.event", feature_type: "all_features" }
    end

    context "#new" do
      test "it creates an instance" do
        assert DeadLetterJob::CacheData.new(
          state: DeadLetterJob::CacheData::STATE_SCHEDULED,
          job_class: @target_job_type,
          arguments: @target_job_inputs,
          scheduled_time: Time.now.to_f
        ).is_a?(DeadLetterJob::CacheData)
      end
    end

    context "#key" do
      test "generates key per job class and arguments" do
        assert DeadLetterJob::CacheData::CACHE_KEY_TEMPLATE % {
          target_job_type: @target_job_type.name,
          target_job_inputs: @target_job_inputs
        }, DeadLetterJob::CacheData.new(
          state: DeadLetterJob::CacheData::STATE_SCHEDULED,
          job_class: @target_job_type,
          arguments: @target_job_inputs,
          scheduled_time: Time.now.to_f
        ).key
      end
    end

    context "#performed?" do
      test "returns true if marked with state :performed" do
        cache_data = DeadLetterJob::CacheData.new(
          state: DeadLetterJob::CacheData::STATE_SCHEDULED,
          job_class: @target_job_type,
          arguments: @target_job_inputs,
          scheduled_time: Time.now.to_f
        )
        refute cache_data.performed?

        cache_data.state = DeadLetterJob::CacheData::STATE_PERFORMED
        assert cache_data.performed?
      end
    end

    context "#exists?" do
      test "returns true if data already saved in KV" do
        cache_data = DeadLetterJob::CacheData.new(
          state: DeadLetterJob::CacheData::STATE_SCHEDULED,
          job_class: @target_job_type,
          arguments: @target_job_inputs,
          scheduled_time: Time.now.to_f
        )
        refute cache_data.exists?

        cache_data.save!
        assert cache_data.exists?
      end
    end

    context "#save!" do
      test "stores cache data in kv" do
        scheduled_time = Time.now.to_f
        cache_data = DeadLetterJob::CacheData.new(
          state: DeadLetterJob::CacheData::STATE_SCHEDULED,
          job_class: @target_job_type,
          arguments: @target_job_inputs,
          scheduled_time: Time.now.to_f
        )
        cache_data.save!

        cache_data_from_kv = SecurityCenter::KV.store.get(cache_data.key).value { nil }
        refute_nil cache_data_from_kv

        parsed_data = DeadLetterJob::CacheData.from_json(cache_data_from_kv)
        refute_nil parsed_data
        assert_equal cache_data.state, T.must(parsed_data).state
        assert_equal cache_data.job_class, T.must(parsed_data).job_class
        assert_equal cache_data.arguments, T.must(parsed_data).arguments
        assert_equal cache_data.scheduled_time, T.must(parsed_data).scheduled_time
      end
    end

    context "#from_json" do
      test "returns instance of CacheData for valid input" do
        assert DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "state" => "scheduled",
            "job_class" => "SecurityCenter::RepositorySyncJob",
            "arguments" => { "repository_id" => 1, "source_event" => "sample.event", "feature_type" => "all_features" },
            "scheduled_time" => 1687818422.2529898
          }
        )).is_a?(DeadLetterJob::CacheData)
      end

      test "returns nil if input is empty string" do
        assert_nil DeadLetterJob::CacheData.from_json("")
      end

      test "returns nil if input is not json" do
        assert_nil DeadLetterJob::CacheData.from_json("test:1,woof:2")
      end

      test "returns nil if input is empty json" do
        assert_nil DeadLetterJob::CacheData.from_json("{}")
      end

      test "returns nil if input is missing state" do
        assert_nil DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "job_class" => "SecurityCenter::RepositorySyncJob",
            "arguments" => { "repository_id" => 1, "source_event" => "sample.event", "feature_type" => "all_features" },
            "scheduled_time" => 1687818422.2529898
          }
        ))
      end

      test "returns nil if input contains wrong state" do
        assert_nil DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "state" => "woof",
            "job_class" => "SecurityCenter::RepositorySyncJob",
            "arguments" => { "repository_id" => 1, "source_event" => "sample.event", "feature_type" => "all_features" },
            "scheduled_time" => 1687818422.2529898
          }
        ))
      end

      test "returns nil if input is missing job class" do
        assert_nil DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "state" => "scheduled",
            "arguments" => { "repository_id" => 1, "source_event" => "sample.event", "feature_type" => "all_features" },
            "scheduled_time" => 1687818422.2529898
          }
        ))
      end

      test "returns nil if input is having unknown job class" do
        assert_nil DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "state" => "scheduled",
            "job_class" => "woof::woof",
            "arguments" => { "repository_id" => 1, "source_event" => "sample.event", "feature_type" => "all_features" },
            "scheduled_time" => 1687818422.2529898
          }
        ))
      end

      test "returns nil if input is having non ApplicationJob class" do
        assert_nil DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "state" => "scheduled",
            "job_class" => "NonApplicationJobTestClass",
            "arguments" => { "repository_id" => 1, "source_event" => "sample.event", "feature_type" => "all_features" },
            "scheduled_time" => 1687818422.2529898
          }
        ))
      end

      test "returns nil if input is missing arguments" do
        assert_nil DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "state" => "scheduled",
            "job_class" => "SecurityCenter::RepositorySyncJob",
            "scheduled_time" => 1687818422.2529898
          }
        ))
      end

      test "returns nil if input have non-hash value for arguments" do
        assert_nil DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "state" => "scheduled",
            "job_class" => "SecurityCenter::RepositorySyncJob",
            "arguments" =>  "woof",
            "scheduled_time" => 1687818422.2529898
          }
        ))
      end

      test "returns nil if input is missing scheduled_time" do
        assert_nil DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "state" => "scheduled",
            "job_class" => "SecurityCenter::RepositorySyncJob",
            "arguments" => { "repository_id" => 1, "source_event" => "sample.event", "feature_type" => "all_features" }
          }
        ))
      end

      test "returns nil if input has string value for scheduled_time" do
        assert_nil DeadLetterJob::CacheData.from_json(JSON.generate(
          {
            "state" => "scheduled",
            "job_class" => "SecurityCenter::RepositorySyncJob",
            "arguments" => { "repository_id" => 1, "source_event" => "sample.event", "feature_type" => "all_features" },
            "scheduled_time" => "woof"
          }
        ))
      end
    end
  end

  class DeadLetterJobTest < GitHub::TestCase
    include JobTestHelper
    include DogstatsTestHelpers

    fixtures do
      @target_job_type = ::SecurityCenter::RepositorySyncJob
      @target_job_inputs = { repository_id: 1, source_event: "sample.event", feature_type: "all_features" }
    end

    context "#schedule_for_retry" do
      test "stores scheduled job in KV cache" do
        DeadLetterJob.schedule_for_retry(job_class: @target_job_type, arguments: @target_job_inputs)

        cache_key = DeadLetterJob::CacheData::CACHE_KEY_TEMPLATE % {
          target_job_type: @target_job_type.name,
          target_job_inputs: @target_job_inputs
        }
        cache_data_from_kv = SecurityCenter::KV.store.get(cache_key).value { nil }
        refute_nil cache_data_from_kv
        assert_dogstats_increment 1, "security_center.dead_letter_job.job_scheduled_for_retry"
      end

      test "logs if job was scheduled before" do
        DeadLetterJob::CacheData.new(
          state: DeadLetterJob::CacheData::STATE_SCHEDULED,
          job_class: @target_job_type,
          arguments: @target_job_inputs,
          scheduled_time: Time.now.to_f
        ).save!

        DeadLetterJob.schedule_for_retry(job_class: @target_job_type, arguments: @target_job_inputs)

        cache_key = DeadLetterJob::CacheData::CACHE_KEY_TEMPLATE % {
          target_job_type: @target_job_type.name,
          target_job_inputs: @target_job_inputs
        }
        cache_data_from_kv = SecurityCenter::KV.store.get(cache_key).value { nil }
        refute_nil cache_data_from_kv

        assert_dogstats_increment 1, "security_center.dead_letter_job.scheduled_job_exists"
        assert_dogstats_increment 1, "security_center.dead_letter_job.job_scheduled_for_retry"
      end
    end

    context "#perform" do
      test "Enqueues target job and mark it as performed" do
        data_before_job = DeadLetterJob::CacheData.new(
          state: DeadLetterJob::CacheData::STATE_SCHEDULED,
          job_class: @target_job_type,
          arguments: @target_job_inputs,
          scheduled_time: 2.hours.ago.to_f
        )
        data_before_job.save!

        @target_job_type.any_instance.expects(:perform).with(has_entries(@target_job_inputs)).once
        assert_performed_jobs 2, only: [@target_job_type, DeadLetterJob] do
          DeadLetterJob.perform_later
        end

        data_from_kv = SecurityCenter::KV.store.get(data_before_job.key).value { nil }
        data_after_job = DeadLetterJob::CacheData.from_json(data_from_kv)

        refute_nil data_after_job
        refute_equal data_before_job.state, T.must(data_after_job).state
        assert_equal DeadLetterJob::CacheData::STATE_PERFORMED, T.must(data_after_job).state
        assert_equal data_before_job.job_class, T.must(data_after_job).job_class
        assert_equal data_before_job.arguments, T.must(data_after_job).arguments
        assert_equal data_before_job.scheduled_time, T.must(data_after_job).scheduled_time

        assert_dogstats_increment 1, "security_center.dead_letter_job.scheduled_job_performed"
        refute_dogstats_increment "security_center.dead_letter_job.scheduled_job_skipped"
        refute_dogstats_increment "security_center.dead_letter_job.no_scheduled_job_found"
      end

      test "Does not enqueue target job if it was marked as performed" do
        data_before_job = DeadLetterJob::CacheData.new(
          state: DeadLetterJob::CacheData::STATE_PERFORMED,
          job_class: @target_job_type,
          arguments: @target_job_inputs,
          scheduled_time: 2.hours.ago.to_f
        )
        data_before_job.save!

        assert_performed_jobs 1, only: DeadLetterJob do
          assert_enqueued_jobs 0, only: @target_job_type do
            DeadLetterJob.perform_later
          end
        end

        refute_dogstats_increment "security_center.dead_letter_job.scheduled_job_performed"
        refute_dogstats_increment "security_center.dead_letter_job.scheduled_job_skipped"
        assert_dogstats_increment 1, "security_center.dead_letter_job.no_scheduled_job_found"
      end

      test "Does not enqueue target job if it has not passed minimal wait time" do
        data_before_job = DeadLetterJob::CacheData.new(
          state: DeadLetterJob::CacheData::STATE_SCHEDULED,
          job_class: @target_job_type,
          arguments: @target_job_inputs,
          scheduled_time: 15.minutes.ago.to_f
        )
        data_before_job.save!

        assert_performed_jobs 1, only: DeadLetterJob do
          assert_enqueued_jobs 0, only: @target_job_type do
            DeadLetterJob.perform_later
          end
        end

        refute_dogstats_increment "security_center.dead_letter_job.scheduled_job_performed"
        assert_dogstats_increment 1, "security_center.dead_letter_job.scheduled_job_skipped"
        refute_dogstats_increment "security_center.dead_letter_job.no_scheduled_job_found"
      end
    end
  end
end
