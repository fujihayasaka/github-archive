# typed: strict
# frozen_string_literal: true

module Api::App::NotificationsDependency
  extend T::Helpers
  requires_ancestor { Api::App::ErrorDependency }

  # Halts the request because notifications are unavailable.
  #
  sig { void }
  def deliver_notifications_unavailable!
    deliver_error! 503
  end
end
