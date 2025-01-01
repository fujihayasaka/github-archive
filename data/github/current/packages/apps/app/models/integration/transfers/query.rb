# typed: strict
# frozen_string_literal: true

class Integration
  module Transfers
    class Query

      sig { params(transfer_to: String).returns(T.nilable(T.any(User, Organization, Business))) }
      def self.find_target_by_params(transfer_to:)
        type, id = transfer_to.split("/")

        case type
        when "User"
          User.find_by(id: id)
        when "Organization"
          Organization.find_by(id: id)
        when "Business"
          Business.find_by(id: id)
        else
          nil
        end
      end

    end
  end
end
