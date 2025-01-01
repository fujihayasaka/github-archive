# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::EmailOptInOutComponent < ApplicationComponent

  sig { params(entity: T.any(::Organization, ::Business), submit_path: String, notifications: T.nilable(String)).void }
  def initialize(entity:, submit_path:, notifications: nil)
    @entity = T.let(entity, T.any(::Organization, ::Business))
    @submit_path = submit_path
    @notifications = notifications
  end

  sig { returns(T::Boolean) }
  def opted_out?
    if @notifications == "enabled"
      return false
    elsif @notifications == "disabled"
      return true
    end
    Copilot.copilot_communication_opt_out?(@entity)
  end

  sig { returns(T::Boolean) }
  def can_toggle?
    return false if has_parent_business?
    true
  end

  sig { returns(String) }
  def opt_out_behavior_msg
    opted_out? ? "Enable Copilot email notifications" : "Disable Copilot email notifications"
  end

  sig { returns(Symbol) }
  def button_type
    opted_out? ? :secondary : :danger
  end

  private

  sig { returns(T::Boolean) }
  def has_parent_business?
    @entity.is_a?(::Organization) && @entity.business.present?
  end
end
