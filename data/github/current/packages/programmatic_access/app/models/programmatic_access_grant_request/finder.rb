# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrantRequest
  class Finder < ProgrammaticAccessGrant::Finder

    # params - The Hash options used to filter (Organization|User)ProgrammaticAccessGrantRequest records fetched.
    #           :target           - The target a grant is associated with.
    #           :target_type      - The target type a grant is associated with (ex: "Organization" or "User").
    #           :repository       - The repository a grant is associated with.
    #           :owner            - A single or array of Users that are the owners of the grants.
    #           :permission       - A permission associated with a grant.
    #           :access           - An access associated with a grant.
    #           :last_used_before - The time that grants were last used before.
    #           :last_used_after  - The time that grants were last used after.
    #
    # Example
    # params = {
    #            :target => Organization.first,
    #            :repository => Repository.first,
    #            :permission => { "actions" => :read }
    #          }
    #
    # NOTE: In order to determine which (Organization|User)ProgrammaticAccessGrantRequest model to query, you must
    # provide at least one of:
    #                         - :target
    #                         - :repository
    #                         - :target_type
    #
    # Returns a scope of (Organization|User)ProgrammaticAccessGrantRequest records.
    def initialize(params: {})
      super
    end

    def set_grantable_klass
      return @grantable_klass if @grantable_klass

      case target_type
      when "Organization"
        @grantable_klass = OrganizationProgrammaticAccessGrantRequest
      when "User"
        @grantable_klass = UserProgrammaticAccessGrantRequest
      else
        raise "Invalid target type: #{target_type.class.name}"
      end
    end

    def with_target(scope)
      return scope unless @target

      case target
      when Organization
        scope.where(organization_id: @target.id)
      else
        scope.where(target_id: @target.id)
      end
    end
  end
end
