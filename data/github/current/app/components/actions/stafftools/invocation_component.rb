# typed: strict
# frozen_string_literal: true

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class Actions::Stafftools::InvocationComponent < ApplicationComponent
  include GitHub::Memoizer

  sig { returns(String) }
  attr_reader :path

  sig { params(blocked: T::Boolean, path: String).void }
  def initialize(blocked:, path:)
    @blocked = blocked
    @path = path
  end

  private

  sig { returns(T::Boolean) }
  def render?
    GitHub.actions_enabled?
  end

  sig { returns(T::Boolean) }
  memoize def action_invocation_blocked?
    @blocked
  end

  sig { returns(Symbol) }
  def form_method
    action_invocation_blocked? ? :post : :delete
  end

  sig { returns(String) }
  def form_action
    action_invocation_blocked? ? "Unblock" : "Block"
  end

  sig { returns(String) }
  def blocked_state
    action_invocation_blocked? ? "blocked" : "not blocked"
  end

  sig { returns(String) }
  def test_selector
    action_invocation_blocked? ? "admin-actions-unblock-invocations-button" : "admin-actions-block-invocations-button"
  end
end
