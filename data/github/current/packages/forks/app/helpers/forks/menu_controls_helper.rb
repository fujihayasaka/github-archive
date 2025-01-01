# typed: true
# frozen_string_literal: true

# An abstract helper to assist with consistent formatting of
# forks search options, as well as helping to bind them to the
# forks/search-control-menu element.
module Forks::MenuControlsHelper
  extend T::Sig
  extend T::Helpers
  abstract!

  requires_ancestor { ApplicationComponent }

  sig { abstract.params(option: T.untyped).returns(T::Boolean) }
  def selected?(option); end

  sig { abstract.params(option: T.untyped).returns(String) }
  def option_path(option); end

  sig { abstract.returns(String) }
  def control_menu_target; end

  def list_item_args_for_option(option)
    is_selected = selected?(option)
    {
      selected: is_selected,
      font_weight: is_selected ? :bold : :normal,
      href: option_path(option),
      data: is_selected ? js_data(option) : nil,
    }
  end

  def js_data(option)
    { target: "search-control-menu.#{control_menu_target}", value: option }
  end
end
