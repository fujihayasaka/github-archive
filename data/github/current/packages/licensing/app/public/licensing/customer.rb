# typed: strict
# frozen_string_literal: true

module Licensing
  module Customer

    sig { params(entity: T.any(::Organization, ::Repository, ::Team, ::User, ::Business)).returns(T.nilable(Integer)) }
    def self.id_for(entity)
      case entity
      when ::Organization, ::Team
        entity.licensed_customer_id
      when ::User
        nil
      when ::Business
        entity.customer_id
      when ::Repository
        entity.organization&.licensed_customer_id
      end
    end
  end
end
