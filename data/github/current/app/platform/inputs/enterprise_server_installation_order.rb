# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class EnterpriseServerInstallationOrder < Platform::Inputs::Base
      docs_category :enterprise_admin
      description "Ordering options for Enterprise Server installation connections."

      argument :field, Enums::EnterpriseServerInstallationOrderField, "The field to order Enterprise Server installations by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
