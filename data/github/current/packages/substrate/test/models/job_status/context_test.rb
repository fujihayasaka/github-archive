# typed: true
# frozen_string_literal: true

require "test_helper"

class JobStatusContextTest < GitHub::TestCase

  class JobStatusWithContext < JobStatus
    include JobStatus::Context
  end

  context "#initialize" do
    test "sets context with given value" do
      context = { foo: 1, bar: 2 }
      job_status = JobStatusWithContext.new(context:)
      assert_equal context, job_status.context
    end
  end

  context "#as_json" do
    test "merges a non-empty context object into the result" do
      context = { foo: 1, bar: 2 }
      job_status = JobStatusWithContext.new
      job_status.context = context

      serialized_status = JSON.parse(job_status.to_json).deep_symbolize_keys
      assert serialized_status.key?(:context)
      assert_equal context, serialized_status[:context]
    end

    test "does not include an empty context object in the result" do
      job_status = JobStatusWithContext.new
      job_status.context = {}
      refute JSON.parse(job_status.to_json).key?("context")
    end
  end
end
