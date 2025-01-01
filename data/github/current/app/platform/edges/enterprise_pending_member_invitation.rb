# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class EnterprisePendingMemberInvitation < Edges::Base
      node_type Objects::OrganizationInvitation
      description "An invitation to be a member in an enterprise organization."
    end
  end
end
