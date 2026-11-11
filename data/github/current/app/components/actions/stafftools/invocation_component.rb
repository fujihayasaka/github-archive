# typed: strict
# frozen_string_literal: true

# rubocop:disable ViewComponent/EncouragePreviewsForScannableComponents
class Actions::Stafftools::InvocationComponent < ApplicationComponent
  include GitHub::Memoizer

  sig { returns(String) }
  attr_reader :path

  sig { params(blocked: T::Boolean, path: String, blocked_by_network_root: T::Boolean).void }
  def initialize(blocked:, path:, blocked_by_network_root: false)
    @blocked = blocked
    @blocked_by_network_root = blocked_by_network_root
    @path = path
  end

  private

  sig { returns(T::Boolean) }
  def render?
    GitHub.actions_enabled?
  end

  sig { returns(T::Boolean) }
  memoize def action_invocation_blocked?
    @blocked || @blocked_by_network_root
  end

  sig { returns(T::Boolean) }
  def blocked_by_network_root?
    @blocked_by_network_root
  end

  sig { returns(T::Boolean) }
  def button_disabled?
    blocked_by_network_root?
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
    if blocked_by_network_root?
      "blocked by the root repository in the fork network"
    elsif action_invocation_blocked?
      "blocked"
    else
      "not blocked"
    end
  end

  sig { returns(String) }
  def test_selector
    action_invocation_blocked? ? "admin-actions-unblock-invocations-button" : "admin-actions-block-invocations-button"
  end
end
