# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class JobStates < Platform::Enums::Base
      visibility :internal

      description "The possible states of a background job."

      value "PENDING", "The background job is pending", value: "pending"
      value "QUEUED", "The background job is queued", value: "queued"
      value "STARTED", "The background job has started", value: "started"
      value "SUCCESS", "The background job has succeeded", value: "success"
      value "ERROR", "The background job has errored", value: "error"
    end
  end
end
