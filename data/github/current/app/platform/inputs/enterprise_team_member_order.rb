# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseTeamMemberOrder < Platform::Inputs::Base
      docs_category :enterprise_admin
      description "Ordering options for enterprise team member connections."
      docs_category :enterprise_admin

      argument :field, Enums::EnterpriseTeamMemberOrderField, "The field to order enterprise team members by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
