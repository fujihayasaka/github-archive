# typed: true
# frozen_string_literal: true

module Actions
  module Environments
    class DeploymentProtectionLogEnvironmentsComponent < ApplicationComponent
      include GateRequestHelper

      def initialize(environments:)
        @environments = environments
      end
    end
  end
end
