# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseServerUserAccountsUploadOrder < Platform::Inputs::Base
      description "Ordering options for Enterprise Server user accounts upload connections."

      argument :field, Enums::EnterpriseServerUserAccountsUploadOrderField, "The field to order user accounts uploads by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
