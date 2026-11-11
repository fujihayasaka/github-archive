# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class AppOrder < Platform::Inputs::Base
      docs_category :apps
      description "Ordering options for app connections."

      visibility :internal

      argument :field, Enums::AppOrderField, "The field to order apps by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
