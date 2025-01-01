# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class IssueTypes < GH::Domain::Base
      ISSUES_READ_BATCH_SIZE = 1000

      ISSUES_WRITE_BATCH_SIZE = 100

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

      # Finds an issue type by its name (case-insensitive) within a given organization.
      sig { params(org: T.any(Integer, Orgs::IOrganization), name: String).returns(T.nilable(IIssueType)) }
      def by_organization_and_name(org, name)
        by_organization(org).find { |issue_type| issue_type.name&.casecmp(name)&.zero? }
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

      # When transferring repo owner, destroys any issue types on issues that do not exist for the new owner.
      # Updates the issue type on issues that do exist for the new owner to point to the new owner's issue type.
      # rubocop:disable Metrics/MethodLength
      sig do
        params(
          repo_id: Integer,
          old_owner: T.any(Orgs::IOrganization, Users::IUser),
          new_owner: T.any(Orgs::IOrganization, Users::IUser),
          actor: T.nilable(Users::IUser)
        )
        .void
      end
      def transfer_issue_types_for_repo(repo_id:, old_owner:, new_owner:, actor:)
        return unless old_owner.organization?

        new_owner_issue_types = new_owner.is_a?(Orgs::IOrganization) ? by_organization(new_owner) : []
        old_owner_issue_types = old_owner.is_a?(Orgs::IOrganization) ? by_organization(old_owner) : []

        issue_type_name_map = old_owner_issue_types.each_with_object({}) do |old_type, map|
          next unless old_type.enabled?
          new_type = new_owner_issue_types.find { |nt| nt.enabled? && nt.name&.casecmp(old_type&.name || "")&.zero? }
          map[old_type.id] = new_type.id if new_type
        end

        issues_to_reindex = []
        issues_with_types_to_delete = []
        issue_types_to_update = {}

        Issue.where(repository_id: repo_id).in_batches(of: ISSUES_READ_BATCH_SIZE).each do |batch|
          batch.each do |issue|
            next unless issue.issue_type_id
            # If the transfer orchestration exits and retries, ensure we don't update issue's type if the issue type belongs to the new owner
            next if new_owner_issue_types.any? { |type| type.id == issue.issue_type_id }

            matching_type_id = issue_type_name_map[issue.issue_type_id]
            if matching_type_id
              issue_types_to_update[matching_type_id] ||= []
              issue_types_to_update[matching_type_id] << issue.id
            else
              issues_with_types_to_delete << issue.id
              issues_to_reindex << issue
            end
          end
        end

        issue_types_to_update.each do |issue_type_id, issue_ids|
          Issue.where(repository_id: repo_id, id: issue_ids).in_batches(of: ISSUES_WRITE_BATCH_SIZE).update_all(issue_type_id: issue_type_id)
        end

        if issues_with_types_to_delete.size > 0
          Issue.where(id: issues_with_types_to_delete).in_batches(of: ISSUES_WRITE_BATCH_SIZE).update_all(issue_type_id: nil)
        end

        # Remove any issue type events, so cross-org types are not loaded in the timeline
        IssueEvent.where(repository_id: repo_id, event: IssueEvent::ISSUE_TYPE_EVENTS).in_batches(of: ISSUES_WRITE_BATCH_SIZE).delete_all

        issues_to_reindex.each do |issue|
          issue.synchronize_search_index
        end
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
