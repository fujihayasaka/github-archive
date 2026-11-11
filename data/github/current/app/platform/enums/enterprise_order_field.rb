# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseOrderField < Platform::Enums::Base
      docs_category :enterprise_admin
      description "Properties by which enterprise connections can be ordered."

      value "NAME", "Order enterprises by name", value: "name"
    end
  end
end
