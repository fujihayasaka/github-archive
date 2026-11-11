# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseTeamOrganizationSelectionType < Platform::Enums::Base
      docs_category :enterprise_admin
      description "The possible organization selection types for an enterprise team."
      docs_category :enterprise_admin

      value "DISABLED", "The team is not associated with any organizations.", value: "disabled"
      value "ALL", "The team is associated with all organizations in the enterprise.", value: "all"
      value "SELECTED", "The team is associated with selected organizations.", value: "selected"
    end
  end
end
