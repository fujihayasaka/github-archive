# typed: true
# frozen_string_literal: true

module Platform
  module ResourceUtils
    def self.is_dashboard_type?(resource)
      resource.is_a?(Platform::DashboardResource) || resource.is_a?(Platform::InternalDashboardResource)
    end
  end
end
