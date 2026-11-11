
# typed: true
# frozen_string_literal: true

module Platform
  class InternalDashboardResource < InternalResource
    def initialize(resource:)
      super
      raise Platform::Errors::Internal, "resource must be a Platform::DashboardResource" unless resource.is_a?(Platform::DashboardResource)
    end
  end
end
