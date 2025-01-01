# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class PackageVersionOrder < Platform::Inputs::Base
      description "Ways in which lists of package versions can be ordered upon return."

      argument :field, Enums::PackageVersionOrderField, "The field in which to order package versions by.", required: false
      argument :direction, Enums::OrderDirection, "The direction in which to order package versions by the specified field.", required: false
    end
  end
end
