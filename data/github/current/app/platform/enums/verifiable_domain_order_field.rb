# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class VerifiableDomainOrderField < Platform::Enums::Base
      docs_category :orgs
      description "Properties by which verifiable domain connections can be ordered."

      value "DOMAIN", "Order verifiable domains by the domain name.", value: "domain"
      value "CREATED_AT", "Order verifiable domains by their creation date.", value: "created_at"
    end
  end
end
