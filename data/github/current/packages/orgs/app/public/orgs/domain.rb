# typed: strict
# frozen_string_literal: true

module Orgs
  class Domain < GH::Domain::Base
    accessor Orgs::Domain::Teams

    sig { params(id: Integer).returns(T.nilable(IOrganization)) }
    def by_id(id)  # rubocop:disable GitHub/DocumentationDomainMethod
      return nil if id <= 0

      Organization.active.find_by(id: id.to_i)
    end

    sig { params(name: String).returns(T.nilable(IOrganization)) }
    def by_name(name)  # rubocop:disable GitHub/DocumentationDomainMethod
      return nil if name.blank?

      Organization.active.find_by(login: name)
    end

  end
end
