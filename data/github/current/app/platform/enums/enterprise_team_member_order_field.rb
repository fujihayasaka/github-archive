# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseTeamMemberOrderField < Platform::Enums::Base
      docs_category :enterprise_admin
      description "Properties by which enterprise team member connections can be ordered."
      docs_category :enterprise_admin

      value "ID", "Order enterprise team members by ID.", value: "id"
      value "LOGIN", "Order enterprise team members by login.", value: "login"
      value "CREATED_AT", "Order enterprise team members by creation time.", value: "created_at"
    end
  end
end
