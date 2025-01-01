# typed: true
# frozen_string_literal: true

module Platform
  # A stand-in object representing a dashboard resource,
  # which does not exist for Installations (returns 404),
  # but which may or may not be enabled for the current user
  # via the installation (403 if disabled, success if enabled).
  class DashboardResource < SimpleDelegator
  end
end
