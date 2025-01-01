# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class CodeqlDatabaseOrder < Platform::Inputs::Base
      description "Ordering options for CodeQL database connections."
      visibility :internal

      argument :field, Enums::CodeqlDatabaseOrderField, "The field to order CodeQL databases by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
