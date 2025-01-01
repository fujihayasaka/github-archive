# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DeploymentReviewState < Platform::Enums::Base
      description "The possible states for a deployment review."

      value "APPROVED", "The deployment was approved.", value: "approved"
      value "REJECTED", "The deployment was rejected.", value: "rejected"
    end
  end
end
