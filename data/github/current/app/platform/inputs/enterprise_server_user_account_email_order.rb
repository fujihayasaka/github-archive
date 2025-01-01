# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseServerUserAccountEmailOrder < Platform::Inputs::Base
      description "Ordering options for Enterprise Server user account email connections."

      argument :field, Enums::EnterpriseServerUserAccountEmailOrderField, "The field to order emails by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
