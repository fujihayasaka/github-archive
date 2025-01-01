# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    class SidePanel::NavList < Primer::Beta::NavList
      status :experimental

      renders_many :experimental_groups, SidePanel::NavList::Group

      def items
        super + experimental_groups
      end
    end
  end
end
