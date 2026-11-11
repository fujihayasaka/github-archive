# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseServerUserAccountOrder < Platform::Inputs::Base
      description "Ordering options for Enterprise Server user account connections."

      argument :field, Enums::EnterpriseServerUserAccountOrderField, "The field to order user accounts by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
