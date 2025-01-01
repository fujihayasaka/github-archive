# typed: true
# frozen_string_literal: true

require "test_helper"

module Growth
  class KeyValueTableExpireJobTest < GitHub::TestCase

    test "expiration time is updated when job arg matches the start of the key" do
      key = "user.dismissed_notice.my_notice"
      notice_key_value = Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues.create(key: "user.dismissed_notice.my_notice.1234", value: "timestamp")
      expires_at = Time.new(2023, 4, 20, 12, 0, 0)
      KeyValueTableExpireJob.perform_now(
        key: key,
        model_class_str: "Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues",
        expires_at: expires_at
      )

      assert_equal expires_at, notice_key_value.reload.expires_at
    end

    test "expiration time is not updated when arg does not match the start of the key" do
      key = "user.dismissed_notice.other_notice"
      not_matched_notice_key_value = Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues.create(key: "user.dismissed_notice.my_notice.1234", value: "timestamp")
      another_not_mached_notice_key_value = Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues.create(key: "user.dismissed_notice.notice.55", value: "timestamp")
      matched_notice_key_value = Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues.create(key: "user.dismissed_notice.other_notice.1234", value: "timestamp")

      expires_at = Time.new(2023, 4, 20, 12, 0, 0)
      KeyValueTableExpireJob.perform_now(
        key: key,
        model_class_str: "Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues",
        expires_at: expires_at
      )

      refute not_matched_notice_key_value.reload.expires_at
      refute another_not_mached_notice_key_value.reload.expires_at
      assert_equal expires_at, matched_notice_key_value.reload.expires_at
    end

    test "raises exception for invalid key format" do
      invalid_key = "invalidkey"

      assert_raises(RuntimeError, "Invalid key format: #{invalid_key}") do
        KeyValueTableExpireJob.perform_now(key: invalid_key, model_class_str: "SomeModel")
      end
    end

    test "logs correct value" do
      Timecop.freeze Time.new(2023, 4, 20, 12, 0, 0) do
        GitHub.logger.expects(:info).with(
          "Fetching the next batch of keys to expire",
          "kv.key" => "test_notice.user_notice.1234",
          "kv.model" => "Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues",
          "code.namespace" => "Growth::KeyValueTableExpireJob",
          "code.function" => :next_batch,
          "offset_item_id" => 0,
          "progress" => 0,
        )

        KeyValueTableExpireJob.perform_now(
          key: "test_notice.user_notice.1234",
          model_class_str: "Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues",
        )
      end
    end

    test "sets offset_item_id and enqueues the job for the next batch" do
      key = "user.dismissed_notice.my_notice.1234"
      notice_key_value = Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues.create!(key: key, value: "timestamp")

      Growth::KeyValueTableExpireJob.stub_const(:BATCH_SIZE, 1) do
        job = assert_enqueued_with(job: Growth::KeyValueTableExpireJob) do
          Growth::KeyValueTableExpireJob.perform_now(key: key, model_class_str: "Growth::KeyValueTableExpireJob::GrowthNoticeKeyValues")
        end
        assert_equal notice_key_value.id, job.arguments.first[:offset_item_id]
      end
    end
  end
end
