# typed: strict
# frozen_string_literal: true

module EnterpriseAccounts
  class KV
    class DataStore < ApplicationRecord::Domain::Users
      self.table_name = "enterprise_accounts_key_values"
    end
  end
end
