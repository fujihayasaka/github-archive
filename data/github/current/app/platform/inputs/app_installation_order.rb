# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class AppInstallationOrder < Platform::Inputs::Base
      description "Ordering options for app installation connections."

      visibility :internal

      argument :field, Enums::AppInstallationOrderField, "The field to order app installations by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
