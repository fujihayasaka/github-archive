# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DeploymentState < Platform::Enums::Base
      description "The possible states in which a deployment can be."

      value "ABANDONED", "The pending deployment was not updated after 30 minutes.", value: "abandoned"
      value "ACTIVE",    "The deployment is currently active.",                      value: "active"
      value "DESTROYED", "An inactive transient deployment.",                        value: "destroyed"
      value "ERROR",     "The deployment experienced an error.",                     value: "error"
      value "FAILURE",   "The deployment has failed.",                               value: "failure"
      value "INACTIVE",  "The deployment is inactive.",                              value: "inactive"
      value "PENDING",   "The deployment is pending.",                               value: "pending"
      value "SUCCESS",   "The deployment was successful.",                           value: "success"

      value "QUEUED", "The deployment has queued", value: "queued"
      value "IN_PROGRESS", "The deployment is in progress.", value: "in_progress"
      value "WAITING", "The deployment is waiting.", value: "waiting"
    end
  end
end
