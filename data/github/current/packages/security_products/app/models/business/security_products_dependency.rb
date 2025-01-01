# typed: true
# frozen_string_literal: true

module Business::SecurityProductsDependency
  extend T::Helpers

  # Helper to check if any BlockedSettings are active for this organization
  #   _or_ if we're actively applying configurations.
  #
  sig { returns(T::Boolean) }
  def security_configurations_applying_or_blocked?
    jobs_in_progress? || security_configurations_blocked?
  end

  sig { returns(T::Boolean) }
  def jobs_in_progress?
    T.bind(self, ::Business)

    SecurityProductsEnablement::JobProgressTracker.new(T.must(id)).in_progress?
  end

  sig { returns(T::Boolean) }
  def security_configurations_blocked?
    BlockedSettings.new(T.cast(self, Business)).any?
  end
end
