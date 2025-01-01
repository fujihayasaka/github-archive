# typed: strict
# frozen_string_literal: true

module RoleAssignments
  class FetchActorRoleAssignments
    include GitHub::Memoizer

    sig { returns(BusinessTeam) }
    attr_reader :actor

    PAGE_SIZE = 10

    sig do
      params(
        actor: BusinessTeam
      ).void
    end
    def initialize(actor:)
      @actor = actor
    end

    # for now, only supports directly-assigned roles
    sig { params(page: Integer).returns(Types::ActorRoleAssignment) }
    def paginate_enterprise_role_assignments(page:)
      return Types::ActorRoleAssignment.new(
        actor: Types::Actor.from_model(actor),
        role_assignments: [],
      ) unless business_teams_enabled

      Types::ActorRoleAssignment.new(
        actor: Types::Actor.from_model(actor),
        role_assignments: all_roles
          .paginate(page: page, per_page: PAGE_SIZE)
          .map { |ur| Types::RoleAssignment.new(role: Types::Role.from_model(ur.role), directly_assigned: true) },
      )
    end

    sig { returns(Integer) }
    def total_role_assignments
      all_roles.size
    end

    private

    sig { returns(ActiveRecord::Relation) }
    def all_roles
      UserRole
        .includes(:actor, :role)
        .where(actor_id: actor.id, actor_type: actor.class, target_id: T.must(@actor.business).id, target_type: "Business")
        .order(:role_id)
    end

    sig { returns(T::Boolean) }
    def business_teams_enabled
      T.must(@actor.business).erp_feature_enabled?(:enterprise_teams_crud)
    end
  end
end
