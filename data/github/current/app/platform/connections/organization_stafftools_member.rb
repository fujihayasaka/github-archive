# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class OrganizationStafftoolsMember < Connections::User
      description "A list of users in an organization."
      total_count_field

      def total_count
        @object.parent.account.member_count
      end
    end
  end
end
