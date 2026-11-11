# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class AdvisoryCreditOrder < Platform::Inputs::Base
      docs_category :security_advisories
      visibility :under_development

      description "Ordering options for advisory credits connections"

      argument :field, Enums::AdvisoryCreditOrderField, "The field to order advisory credits by.", required: true
    end
  end
end
