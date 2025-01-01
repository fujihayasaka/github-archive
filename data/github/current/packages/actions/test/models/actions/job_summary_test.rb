# typed: true
# frozen_string_literal: true

require "github-launch"
require "test_helper"
require "monolith-twirp-actionsresults-core"

class Actions::JobSummaryTest < GitHub::TestCase
  test "#initialize" do
    step_summaries = [
      {
        step_record_id: SecureRandom.uuid,
        content: Faker::Movies::StarWars.quote,
        truncated: false,
        created_on: 5.minutes.ago
      },
      {
        step_record_id: SecureRandom.uuid,
        content: Faker::Movies::StarWars.quote,
        truncated: false,
        created_on: 15.minutes.ago
      },
      {
        step_record_id: SecureRandom.uuid,
        content: Faker::Movies::StarWars.quote,
        truncated: false,
        created_on: 10.minutes.ago
      }
    ]

    job_summary = Actions::JobSummary.new(
      truncated: false,
      step_summaries: step_summaries
    )

    refute job_summary.truncated

    sorted_ids = step_summaries.sort_by { |s| s[:created_on] }.pluck(:step_record_id)
    assert_equal sorted_ids, job_summary.step_summaries.pluck(:step_record_id)
  end

  test ".from_hash" do
    hash = {
      "truncated" => false,
      "stepSummaries" => [
        {
          "stepRecordId" => SecureRandom.uuid,
          "contentBase64" => Base64.encode64(Faker::Movies::StarWars.quote),
          "truncated" => false,
          "createdOn" => 5.minutes.ago.iso8601,
        },
        {
          "stepRecordId" => SecureRandom.uuid,
          "contentBase64" => Base64.encode64(Faker::Movies::StarWars.quote),
          "truncated" => false,
          "createdOn" => 15.minutes.ago.iso8601,
        },
        {
          "stepRecordId" => SecureRandom.uuid,
          "contentBase64" => Base64.encode64(Faker::Movies::StarWars.quote),
          "truncated" => false,
          "createdOn" => 10.minutes.ago.iso8601,
        }
      ],
    }

    job_summary = Actions::JobSummary.from_hash(hash)

    assert_equal hash["truncated"], job_summary.truncated
    assert_equal hash["stepSummaries"].length, job_summary.step_summaries.length

    sorted_ids = hash["stepSummaries"].sort_by { |s| DateTime.parse(s["createdOn"]) }.pluck("stepRecordId")
    assert_equal sorted_ids, job_summary.step_summaries.pluck(:step_record_id)

    job_summary.step_summaries.each do |step_summary|
      hash_step_summary = hash["stepSummaries"].find { |hs| hs["stepRecordId"] == step_summary[:step_record_id] }

      assert_equal hash_step_summary["contentBase64"], ::Base64.encode64(step_summary[:content])
      assert_equal hash_step_summary["createdOn"], step_summary[:created_on].utc.iso8601
      assert_equal hash_step_summary["truncated"], step_summary[:truncated]
    end
  end

  test ".from_results_hash" do
    workflow_run_backend_id = "123-abc"
    content = Base64.encode64(Faker::Movies::StarWars.quote)
    created_at = "2022-12-09T23:30:11.262904515Z"

    hash = {
      "workflowJobRunBackendId" => workflow_run_backend_id,
      "isTruncated" => true,
      "stepSummaries" => [
        {
          "content" => content,
          "createdAt" => created_at,
        },
        {
          "isTruncated" => true,
          "content" => content,
          "createdAt" => created_at,
        }
      ]
    }

    job_summary = Actions::JobSummary.from_results_hash(hash)

    assert_equal hash["isTruncated"], job_summary.truncated
    assert_equal hash["stepSummaries"].length, job_summary.step_summaries.length

    job_summary.step_summaries.each_with_index do |step_summary, index|
      hash_step_summary = hash["stepSummaries"][index]

      assert_equal hash_step_summary["content"], ::Base64.encode64(step_summary[:content])
      assert_equal DateTime.parse(hash_step_summary["createdAt"]).to_i, step_summary[:created_on].to_i
      assert_equal (hash_step_summary["isTruncated"] || false), step_summary[:truncated]
    end
  end

  test "#is_truncated?" do
    truncated_job = Actions::JobSummary.new(
      truncated: true,
      step_summaries: [
        {
          step_record_id: SecureRandom.uuid,
          content: Faker::Movies::StarWars.quote,
          truncated: false,
          created_on: DateTime.now
        }
      ]
    )

    assert truncated_job.is_truncated?

    truncated_step = Actions::JobSummary.new(
      truncated: false,
      step_summaries: [
        {
          step_record_id: SecureRandom.uuid,
          content: Faker::Movies::StarWars.quote,
          truncated: true,
          created_on: DateTime.now
        }
      ]
    )

    assert truncated_step.is_truncated?
  end
end
