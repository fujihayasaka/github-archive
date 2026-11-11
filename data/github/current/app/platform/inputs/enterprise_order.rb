# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseOrder < Platform::Inputs::Base
      docs_category :enterprise_admin
      description "Ordering options for enterprises."

      argument :field, Enums::EnterpriseOrderField, "The field to order enterprises by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
