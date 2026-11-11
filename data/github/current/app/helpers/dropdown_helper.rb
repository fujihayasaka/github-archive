# typed: true
# frozen_string_literal: true

module DropdownHelper
  # Internal: Define symbol shorthand to direction class name.
  DROPDOWN_DIRECTIONS = {
    w: "dropdown-menu-w",
    e: "dropdown-menu-e",
    s: "dropdown-menu-s",
    sw: "dropdown-menu-sw",
    se: "dropdown-menu-se",

    west: "dropdown-menu-w",
    east: "dropdown-menu-e",
    southwest: "dropdown-menu-sw",
    southeast: "dropdown-menu-se",
  }

  # if an unreconginzed direction is passed in, don't throw an exception and default to west
  DEFAULT_DROPDOWN_DIRECTION = "dropdown-menu-w"

  # Public: Get dropdown class name for direction.
  #
  # See dropdown.scss
  #
  # direction - Symbol direction in DROPDOWN_DIRECTIONS.
  #
  # Returns String class name.
  def dropdown_menu_class(direction)
    klass = DROPDOWN_DIRECTIONS[direction.to_sym]

    unless klass
      return DEFAULT_DROPDOWN_DIRECTION
    end

    klass
  end
end
