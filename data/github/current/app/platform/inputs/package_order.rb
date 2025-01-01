# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class PackageOrder < Platform::Inputs::Base
      description "Ways in which lists of packages can be ordered upon return."

      argument :field, Enums::PackageOrderField, "The field in which to order packages by.", required: false
      argument :direction, Enums::OrderDirection, "The direction in which to order packages by the specified field.", required: false
    end
  end
end
