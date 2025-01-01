# typed: true
# frozen_string_literal: true

module Sponsorship::StateDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Sponsorship }

  included do
    T.bind(self, T.class_of(Sponsorship))

    workflow :state do
      state :pending, 0 do
        event :payment_completed, transitions_to: :active_test
      end

      # Issue 4692: https://github.com/github/sponsors/issues/4692
      # TODO: rename this to active; currently conflicts with active column
      state :active_test, 1

      # Issue 4691: https://github.com/github/sponsors/issues/4691
      # TODO: Break out the following inactive states - canceled, expired, rejected
      state :inactive_test, 2
    end
  end

  private

  # Private: Called when calling `payment_completed!` for state transition.
  def payment_completed
  end
end
