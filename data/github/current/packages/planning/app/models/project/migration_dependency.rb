# typed: true
# frozen_string_literal: true

class Project
  module MigrationDependency
    extend ActiveSupport::Concern
    extend T::Helpers
    requires_ancestor { Project }

    STATUS_FIELD_MIGRATION_ID = "status"

    def to_memex_specification(card_cutoff_date: 0)
      ActiveRecord::Base.connected_to(role: :reading) do
        GitHub::PrefillAssociations.prefill_associations(
          self,
          [:columns, :project_workflows]
        )

        {
          owner_type: owner_type,
          owner_id: owner_id,
          title: name,
          description: body,
          public: public?,
          status_field: {
            id: STATUS_FIELD_MIGRATION_ID,
            settings: {
              options: columns.map(&:to_memex_specification),
            }
          },
          views: [
            {
              layout: "board",
              visible_fields: [
                "Labels"
              ]
            },
          ],
          permissions: permissions_to_memex_specification,
          items: get_ordered_cards(card_cutoff_date:).map(&:to_memex_specification),
          workflows: ProjectWorkflow.to_memex_specification(project_workflows),
        }.compact
      end
    end

    private

    def permissions_to_memex_specification
      abilities = []

      # Migrate all of the collaborators/teams that have permission to this project
      if owner.is_a?(Repository)
        abilities += Ability.where(subject: owner).map { |ability| ability_to_permission(ability) }
      else
        abilities += Ability.where(subject: self).map { |ability| ability_to_permission(ability) }
      end

      # 1) If the project is owned by an organization, but the organization permissions are set to 'none', then we
      # should migrate the same 'none' base role to the MemexProject.
      has_none_org_permission = owner.is_a?(Organization) && org_permission.nil?
      # 2) Or, if the project is owned by a repository, but the organization that owns the repository has the default
      # repository permission set to 'none', then we should migrate the same 'none' base role to the MemexProject, so
      # that a repo-level project does not automatically become accessible to all organization members.
      has_none_repo_permission = owner.is_a?(Repository) && owner.organization&.default_repository_permission == :none
      if has_none_org_permission || has_none_repo_permission
        abilities.push({
          actor_type: "Organization",
          action: "none",
          actor_id: organization.id,
        })

        # Add creator of project as a "collaborator" if they are not already in the list and the owner is an organization,
        # and the creator is still part of the organization (to avoid granting access to non-org members).
        org = T.let(
          if owner.is_a?(Organization)
            owner
          elsif owner.is_a?(Repository)
            owner.organization
          else
            nil
          end,
          T.nilable(Organization)
        )
        if org&.member?(creator)
          abilities = abilities.reject { |ability| ability[:actor_id] == creator_id }
          # Repository projects are adminable by the user if they are writable by the user, and users with write access
          # can create projects. Therefore, we should make sure the migrated user is an admin.
          abilities.push({
            actor_type: "User",
            action: "admin",
            actor_id: creator_id,
          })
        end
      end

      abilities
    end

    def ability_to_permission(ability)
      {
        actor_type: ability.actor_type,
        action: ability.action,
        actor_id: ability.actor.id,
      }
    end

    # Note here we prefill a number associations so that we can avoid N+1 queries
    def get_ordered_cards(card_cutoff_date: 0)
      GitHub::PrefillAssociations.prefill_associations(columns, [:cards])

      cards_from_columns = columns.each_with_object([]) do |column, cards|
        cards.concat(
          column.cards
            # reject any cards that hasn't been updated in since provided cutoff date
            .reject { |card| (card.updated_at || Float::INFINITY) < card_cutoff_date }
            # use Ruby to sort by priority so we can preload and avoid N+1. The reverse is benchmarked to be faster than reversing in the sort_by.
            .sort_by { |card| card.priority.presence || 0 }.reverse
        )
      end

      GitHub::PrefillAssociations.prefill_associations(
        cards_from_columns,
        [content: [:issues, :pull_requests]]
      )

      cards_from_columns
    end
  end
end
