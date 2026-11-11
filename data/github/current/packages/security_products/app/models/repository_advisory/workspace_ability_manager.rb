# typed: true
# frozen_string_literal: true

# This class co-ordinates the inheritence of abilities from
# the parent repository and advisory unto newly created workspaces
class RepositoryAdvisory::WorkspaceAbilityManager

  # Adds the #apply_abilities method to directly write to the Ability table
  include Ability::Grant::ApplyAbilities

  def initialize(workspace, actor)
    @workspace = workspace
    @actor = actor
  end

  # Important: This method should be *only* be called from a background job
  #            as we need to ensure we throttle on the abilities table due
  #            to the number of rows potentially involved
  def perform
    apply_repo_admin_abilities
    apply_advisory_write_abilities
  end

  private

  def apply_repo_admin_abilities
    workspace_abilities = inheritable_abilities(@workspace.parent_advisory_repository, :admin).map do |inheritable_ability|
      [
        inheritable_ability.actor_id,
        inheritable_ability.actor_type,
        Ability.actions[inheritable_ability.action],
        @workspace.ability_id,
        @workspace.ability_type,
        Ability.priorities[inheritable_ability.priority],
        inheritable_ability.parent_id,
        GitHub::SQL::ArelLiterals::NOW,
        GitHub::SQL::ArelLiterals::NOW,
      ]
    end

    # Apply abilities directly as a batch for performance
    apply_abilities(workspace_abilities, stats_key: :direct)
  end

  def apply_advisory_write_abilities
    inheritable_abilities(@workspace.parent_advisory, :write).each do |inheritable_ability|
      next unless @workspace.parent_advisory_repository.readable_by?(inheritable_ability.actor)

      if @workspace.parent_advisory.external? && inheritable_ability.actor == @workspace.parent_advisory.author
        @workspace.add_vulnerability_reporter(@workspace.parent_advisory.author)
      elsif inheritable_ability.actor.is_a?(Team)
        @workspace.add_team(inheritable_ability.actor, action: :write)
      elsif inheritable_ability.actor == @actor
        @workspace.add_member(inheritable_ability.actor, action: :write)
      else
        RepositoryInvitation.invite_to_repo(inheritable_ability.actor, @actor, @workspace, action: :write)
      end
    end
  end

  def inheritable_abilities(subject, action)
    Authorization.service.direct_abilities_on_subject(subject: subject,
                                                      action: action)
  end
end
