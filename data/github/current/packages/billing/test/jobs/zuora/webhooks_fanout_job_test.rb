# typed: true
# frozen_string_literal: true

require "test_helper"

class Zuora::WebhooksFanoutJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    @webhooks = create_list(:zuora_webhook, 5, :not_recent)
  end

  test "schedules jobs with correct delay for each batch" do
    freeze_time do
      clear_enqueued_jobs

      assert_enqueued_jobs 5, only: ZuoraWebhookJob do
        Zuora::WebhooksFanoutJob.perform_now
      end

      @webhooks.each do |webhook|
        enqueued_job = enqueued_jobs.find do |j|
          j[:job] == ZuoraWebhookJob && j[:args] == [{ "_aj_globalid" => webhook.to_global_id.to_s }]
        end

        refute_nil enqueued_job, "Job for webhook #{webhook.id} was not enqueued"
        actual_delay = enqueued_job[:at] ? enqueued_job[:at] - Time.now.to_f : Time.now.to_f

        assert_operator actual_delay, :>=, 0.minutes
        assert_operator actual_delay, :<=, 5.minutes
      end
    end
  end
end
