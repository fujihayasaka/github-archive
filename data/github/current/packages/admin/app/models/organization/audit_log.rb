# typed: true
# frozen_string_literal: true

class Organization
  class AuditLog
    def initialize(organization)
      @organization = organization
    end

    def search(query = {})
      Audit::Driftwood::Query.new_org_business_query(query.merge(org_id: @organization.id)).execute
    end
  end
end
