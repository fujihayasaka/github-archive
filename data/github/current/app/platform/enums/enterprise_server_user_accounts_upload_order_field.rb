# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseServerUserAccountsUploadOrderField < Platform::Enums::Base
      description "Properties by which Enterprise Server user accounts upload connections can be ordered."

      value "CREATED_AT", "Order user accounts uploads by creation time", value: "created_at"
    end
  end
end
