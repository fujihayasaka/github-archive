# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class EnterpriseFailedInvitation < Edges::Base
      node_type Objects::OrganizationInvitation
      description "A failed invitation to be a member in an enterprise organization."
    end
  end
end
