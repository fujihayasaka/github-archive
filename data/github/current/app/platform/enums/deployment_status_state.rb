# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DeploymentStatusState < Platform::Enums::Base
      description "The possible states for a deployment status."

      value "PENDING",  "The deployment is pending.",           value: "pending"
      value "SUCCESS",  "The deployment was successful.",       value: "success"
      value "FAILURE",  "The deployment has failed.",           value: "failure"
      value "INACTIVE", "The deployment is inactive.",          value: "inactive"
      value "ERROR",    "The deployment experienced an error.", value: "error"
      value "QUEUED",   "The deployment is queued",             value: "queued"
      value "IN_PROGRESS", "The deployment is in progress.",    value: "in_progress"
      value "WAITING", "The deployment is waiting.",            value: "waiting"
    end
  end
end
