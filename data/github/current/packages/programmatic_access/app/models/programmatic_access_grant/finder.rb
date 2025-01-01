# typed: true
# frozen_string_literal: true

module ProgrammaticAccessGrant

  # Finds (Organization|UseR)ProgrammaticAccessGrant records.
  #
  class Finder

    attr_reader :target, :params, :grantable_klass

    # params - The Hash options used to filter (Organization|User)ProgrammaticAccessGrant records fetched.
    #           :target           - The target a grant is associated with.
    #           :target_type      - The target type a grant is associated with (ex: "Organization" or "User").
    #           :repository       - The repository a grant is associated with.
    #           :owner            - A single or array of Users that are the owners of the grants.
    #           :permission       - A permission associated with a grant.
    #           :access           - An access associated with a grant.
    #           :last_used_before - The time that grants were last used before.
    #           :last_used_after  - The time that grants were last used after.
    #           :token_ids        - The IDs to filter grants based on the UserProgrammaticAccess record.
    #
    # Example
    #
    # params = {
    #            :target => Organization.first,
    #            :repository => Repository.first,
    #            :permission => { "actions" => :read }
    #          }
    #
    # NOTE: In order to determine which (Organization|User)ProgrammaticAccessGrant model to query, you must
    # provide at least one of:
    #                         - :target
    #                         - :repository
    #                         - :target_type
    #
    # Returns a scope of (Organization|User)ProgrammaticAccessGrant records.
    def initialize(params: {})
      @target = params[:target] || params[:repository]&.owner
      @params = params
    end

    def perform
      scope = with_repository(set_grantable_klass.all)
      scope = with_target(scope)
      scope = with_owner(scope)
      scope = with_permission(scope)
      scope = with_access(scope)
      scope = last_used_before(scope)
      scope = last_used_after(scope)
      scope = with_token_ids(scope)
      scope
    end

    protected

    def set_grantable_klass
      return @grantable_klass if @grantable_klass

      case target_type
      when "Organization"
        @grantable_klass = OrganizationProgrammaticAccessGrant
      when "User"
        @grantable_klass = UserProgrammaticAccessGrant
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
        scope.where(user_id: @target.id)
      end
    end

    def target_type
      if @target
        @target.class.name
      else
        @params[:target_type]
      end
    end

    private

    def with_repository(scope)
      return scope unless @params[:repository].present?

      @grantable_klass.with_repository(@params[:repository])
    end

    def with_owner(scope)
      return scope unless @params[:owner].present?

      owner_ids = if @params[:owner].respond_to?(:each)
        @params[:owner].map(&:id)
      else
        @params[:owner].id
      end

      scope
        .joins(:user_programmatic_access)
        .where(user_programmatic_accesses: { user_id: owner_ids })
    end

    def with_permission(scope)
      return scope unless @params[:permission].present?

      resource, action = @params[:permission].first
      resource_parent = Permissions::ResourceRegistry.parent_of(resource)
      return @model_klass.none if resource_parent.nil?

      subject_types = "#{resource_parent}::Resources".constantize.all_prefixed_subject_types([resource])

      scope
        .joins(:permission_records)
        .where(permission_records: { subject_type: subject_types, action: Permission::ACTION_RANKING[action.to_sym].. })
    end

    def with_access(scope)
      return scope unless @params[:access].present?

      scope.where(user_programmatic_access: @params[:access])
    end

    def last_used_before(scope)
      return scope unless @params[:last_used_before].present?

      before = if @params[:last_used_before].is_a? String
        DateTime.parse(@params[:last_used_before])
      else
        @params[:last_used_before]
      end

      scope
        .joins(:user_programmatic_access)
        .where("user_programmatic_accesses.accessed_at < ?", before)
    end

    def last_used_after(scope)
      return scope unless @params[:last_used_after].present?

      after = if @params[:last_used_after].is_a? String
        DateTime.parse(@params[:last_used_after])
      else
        @params[:last_used_after]
      end

      scope
        .joins(:user_programmatic_access)
        .where("user_programmatic_accesses.accessed_at > ?", after)
    end

    def with_token_ids(scope)
      return scope unless @params[:token_ids].present?

      scope
        .joins(:user_programmatic_access)
        .where(user_programmatic_access: { id: @params[:token_ids] })
    end
  end
end
