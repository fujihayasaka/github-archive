# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class Repository < ApplicationRecord::Domain::SecurityProductsEnablement
    self.table_name = "security_products_enablement_repositories"
    self.primary_key = "repository_id"
  end
end
