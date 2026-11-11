# typed: strict
# frozen_string_literal: true

class OrganizationInvitation
  class PrivateRelation
    sig { params(token: String).returns(OrganizationInvitation::PrivateRelation) }
    def find_by_token(token); end
  end
end
