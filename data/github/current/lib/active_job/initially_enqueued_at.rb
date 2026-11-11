# typed: false
# frozen_string_literal: true

# Adds initially_enqueued_at attribute that does not change through retries
module ActiveJob
  module InitiallyEnqueuedAt
    extend ActiveSupport::Concern

    included do
      before_enqueue do
        initially_enqueued_at
      end
    end

    def initially_enqueued_at
      @initially_enqueued_at ||= Time.now.utc
    end

    def serialize
      super.merge("initially_enqueued_at" => initially_enqueued_at.to_f)
    end

    def deserialize(job_data)
      super
      @initially_enqueued_at = Time.at(job_data["initially_enqueued_at"]) if job_data["initially_enqueued_at"]
    end
  end
end
