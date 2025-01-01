# typed: strict
# frozen_string_literal: true

class Billing::Settings::DowngradeMenuButtonComponent < ApplicationComponent

  include PlanDowngradeHelper

  sig { returns(GitHub::Plan) }
  attr_reader :current_plan

  sig { returns(GitHub::Plan) }
  attr_reader :new_plan

  sig { returns(String) }
  attr_reader :dialog_id

  sig { params(current_plan: GitHub::Plan, new_plan: GitHub::Plan, dialog_id: String, data: T::Hash[String, String]).void }
  def initialize(current_plan:, new_plan:, dialog_id: "plan-downgrade-dialog-#{new_plan.name}", data: {})
    @current_plan = T.let(current_plan, GitHub::Plan)
    @new_plan = T.let(new_plan, GitHub::Plan)
    @dialog_id = T.let(dialog_id, String)
    @data = T.let(data, T::Hash[String, String])
  end

  sig { returns(T::Hash[Symbol, T.any(T::Hash[String, String], Symbol, String)]) }
  def button_props
    {
      scheme: :link,
      classes: "dropdown-item",
      test_selector: "downgrade-dialog-button",
      data: {
        "show-dialog-id": @dialog_id
      }.merge(@data),
      role: "menuitem",
    }
  end
end
