# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseTeamOrganizationOrderField < Platform::Enums::Base
      docs_category :enterprise_admin
      description "Properties by which enterprise team organization connections can be ordered."
      docs_category :enterprise_admin

      value "ID", "Order enterprise team organizations by ID.", value: "id"
      value "LOGIN", "Order enterprise team organizations by login.", value: "login"
      value "CREATED_AT", "Order enterprise team organizations by creation time.", value: "created_at"
    end
  end
end
