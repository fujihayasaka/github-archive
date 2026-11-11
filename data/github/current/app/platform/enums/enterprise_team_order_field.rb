# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseTeamOrderField < Platform::Enums::Base
      docs_category :enterprise_admin
      description "Properties by which enterprise team connections can be ordered."
      docs_category :enterprise_admin

      value "ID", "Order enterprise teams by ID.", value: "id"
      value "NAME", "Order enterprise teams by name.", value: "name"
      value "CREATED_AT", "Order enterprise teams by creation time.", value: "created_at"
    end
  end
end
