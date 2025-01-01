# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions::Core::V1
  class GetRepositoryEventDetails
    include GitHub::Memoizer

    attr_reader :req

    def self.call(request)
      new(request).call
    end

    def initialize(request)
      @req = request
    end

    def call
      return Twirp::Error.invalid_argument("missing repository_id", argument: "repository_id") if req.repository_id.blank?
      return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository
      return Twirp::Error.not_found("repository owner does not exist") unless repository.owner

      # Create an event payload similar to Hook::Payload#to_hash
      event = {
        repository: Api::Serializer.serialize(:repository_with_custom_properties_hash, repository)
      }

      event[:organization] = Api::Serializer.serialize(:organization_hash, organization) if organization.present?
      event[:enterprise] = Api::Serializer.serialize(:business_hash, enterprise) if enterprise.present?

      {
        event_payload: event.to_json,
      }
    end

    memoize def repository
      if GitHub.flipper[:repos_domain_twirp].enabled?
        Repositories.domain.by_id(req.repository_id)
      else
        Repository.find_by(id: req.repository_id)
      end
    end

    memoize def organization
      repository.owner.organization? ? repository.owner : nil
    end

    def enterprise
      if repository.owner.organization?
        organization&.business
      # in an a multi-tenant context the repo could be owned by a user. In those cases
      # return the current tenant so that enterprise data is still returned in the response
      # can't use GitHub.CurrentTenant because this may be called from an internal API as an unscoped request
      elsif GitHub.multi_tenant_enterprise? && repository.owner.user?
        repository.user.enterprise_managed_business
      end
    end
  end
end
