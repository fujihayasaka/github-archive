# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class IssueTypes < GH::Domain::Base
      extend T::Sig

      # Get enabled IssueTypes for a set of organizations.
      sig { params(org: T.any(Integer, Orgs::IOrganization)).returns(T::Array[Issues::IIssueType]) }
      def by_organization(org)
        result = by_organizations(Array.wrap(org))
        org_id = org.is_a?(Orgs::IOrganization) ? org.id || - 1 : org
        result[org_id] || []
      end

      # Get enabled IssueTypes for a set of organizations.
      sig { params(orgs: T::Array[T.any(Integer, Orgs::IOrganization)]).returns(T::Hash[Integer, T::Array[Issues::IIssueType]]) }
      def by_organizations(orgs)
        org_ids = orgs.map { |org| org.is_a?(Orgs::IOrganization) ? org.id : org }
        result = ::IssueType.batched_scope(:owner, values: org_ids).where(enabled: true).group_by(&:owner_id)

        defaults = orgs.map { |org| [org.is_a?(Orgs::IOrganization) ? org.id || -1 : org, []] }.to_h
        defaults.merge result
      end

      # Check if repository owner has IssueTypes enabled.
      sig { params(owner_or_id: T.any(Integer, Orgs::IOrganization, Users::IUser)).returns(T::Boolean) }
      def is_owner_enabled?(owner_or_id)
        owner = if owner_or_id.is_a?(Integer)
          ::User.find_by(id: owner_or_id)
        else
          owner_or_id
        end

        owner&.organization? && owner.feature_enabled?(:issue_types) || false
      end

      private

      sig { params(repo: Repositories::IRepository, issue_types: T::Array[Issues::IIssueType]).returns(T::Array[Issues::IIssueType]) }
      def filter_private_issue_types(repo, issue_types)
        if !repo.private?
          issue_types.reject { |issue_type| issue_type.private? }
        else
          issue_types
        end
      end
    end
  end
end
