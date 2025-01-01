# typed: true
# frozen_string_literal: true

class Forks::Controls::PeriodComponent < ApplicationComponent
  include Forks::MenuControlsHelper

  OPTIONS = {
    "1mo" => "1 month",
    "6mo" => "6 months",
    "1y" => "1 year",
    "2y" => "2 years",
    "5y" => "5 years",
    "" => "All time",
  }.freeze

  CONTROL_MENU_TARGET = "selectedPeriodOption"

  sig { params(path_resolver: Forks::PathResolver, system_args: Primer::SystemArgumentsValue).void }
  def initialize(path_resolver, **system_args)
    @path_resolver = path_resolver
    @control_state = path_resolver.options
    @threshold = @control_state.period
    @system_args = system_args
  end

  def self.valid_options
    OPTIONS.keys
  end

  private

  attr_reader :system_args, :threshold

  sig { override.params(option: String).returns(T::Boolean) }
  def selected?(option)
    option == @threshold
  end

  sig { override.params(option: String).returns(String) }
  def option_path(option)
    @path_resolver.next_path(period: option)
  end

  def list_item_args_for_option(option)
    is_selected = selected?(option)
    {
      selected: is_selected,
      font_weight: is_selected ? :bold : :normal,
      href: option_path(option),
      data: is_selected ? js_data(option) : nil,
    }
  end

  def control_menu_target
    CONTROL_MENU_TARGET
  end
end
