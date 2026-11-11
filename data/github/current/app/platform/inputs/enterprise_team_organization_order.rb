# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseTeamOrganizationOrder < Platform::Inputs::Base
      docs_category :enterprise_admin
      description "Ordering options for enterprise team organization connections."
      docs_category :enterprise_admin

      argument :field, Enums::EnterpriseTeamOrganizationOrderField, "The field to order organizations by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
