# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CrossReferencedEvent < Platform::Objects::Base
      model_name "CrossReference"
      description "Represents a mention made by one issue or pull request to another."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, cross_reference)
        Promise.all([
          cross_reference.async_source_issue_or_pull_request,
          cross_reference.async_target_issue_or_pull_request,
        ]).then do |source, target|
          next unless source
          next unless target
          Promise.all([
            source.async_repository,
            target.async_repository,
          ]).then do |source_repo, target_repo|
            next unless source_repo
            next unless target_repo
            Promise.all([
              source_repo.async_owner,
              target_repo.async_owner,
              source_repo.async_ip_restricted_private_fork?,
              target_repo.async_ip_restricted_private_fork?,
            ]).then do |source_repo_owner, target_repo_owner, source_ip_restricted_private_fork, target_ip_restricted_private_fork|
              source_repo_org = source_repo_owner.is_a?(::Organization) ? source_repo_owner : nil
              target_repo_org = target_repo_owner.is_a?(::Organization) ? target_repo_owner : nil
              permission.access_allowed?(
                :list_issue_timeline,
                resource: source,
                repo: source_repo,
                current_org: source_repo_org,
                allow_integrations: true,
                allow_user_via_granular_actor: true,
                ip_restricted_private_fork: source_ip_restricted_private_fork,
              ) && permission.access_allowed?(
                :list_issue_timeline,
                resource: target,
                repo: target_repo,
                current_org: target_repo_org,
                allow_integrations: true,
                allow_user_via_granular_actor: true,
                ip_restricted_private_fork: target_ip_restricted_private_fork,
              )
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return false if object.hide_from_user?(permission.viewer)

        Promise.all([
          object.async_source,
          object.async_target,
        ]).then do |source, target|
          next false if source.nil? || target.nil?
          source_type_name = Helpers::NodeIdentification.type_name_from_object(source)
          permission.typed_can_see?(source_type_name, source).then do |can_read_source|
            next false unless can_read_source
            target_type_name = Helpers::NodeIdentification.type_name_from_object(target)
            permission.typed_can_see?(target_type_name, target)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::TimelineEvent

      implements Interfaces::UniformResourceLocatable

      implements_node templates: [[:rcre, :repo_id, :cross_referenced_event_id]], as: "CRE", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |cross_referenced_event|
        promise =
        if cross_referenced_event.is_a?(::Timeline::Placeholder::CrossReference)
          cross_reference_ids = [cross_referenced_event.id]
          ::Issue::Loader::CrossReferences.load_for(@context, cross_reference_ids: cross_reference_ids).then do |cross_references_by_id|
            cross_ref = cross_references_by_id.values.first
            Promise.all([cross_ref.async_source, cross_ref.async_target])
          end
        else
          Promise.all([
            cross_referenced_event.async_source_issue_or_pull_request,
            cross_referenced_event.async_target_issue_or_pull_request,
          ])
        end

        promise.then do |source, target|
          obj = source || target
          {
            prefix: :rcre,
            repo_id: obj&.repository_id,
            cross_referenced_event_id: cross_referenced_event.id
          }
        end
      end

      url_fields description: "The HTTP URL for this pull request." do |cross_ref_event|
        cross_ref_event.async_path_uri
      end

      field :source, Unions::ReferencedSubject, "Issue or pull request that made the reference.", method: :async_source_issue_or_pull_request, null: false

      field :target, Unions::ReferencedSubject, "Issue or pull request to which the reference was made.", method: :async_target_issue_or_pull_request, null: false

      field :referenced_at, Scalars::DateTime, "Identifies when the reference was made.", null: false

      field :will_close_target, Boolean, "Checks if the target will be closed when the source is merged.", method: :async_will_close_target?, null: false

      field :is_cross_repository, Boolean, "Reference originated in a different repository.", method: :async_cross_repository?, null: false
    end
  end
end
