# typed: true
# frozen_string_literal: true

require "scientist"

module Permissions
  module Granters
    class RoleGranter
      include Scientist

      attr_reader :role, :actor, :target, :target_type, :grantor, :conditions

      BATCH_SIZE = 100

      BASE_ROLE_TO_ABILITY = {
        "read": :read,
        "triage": :read,
        "write": :write,
        "maintain": :write,
      }.with_indifferent_access

      class GrantFailure < ::Permissions::Participant::PermissionGrantError; end

      # Public: Initializes a RoleGranter.
      #
      # NOTE: Most of these are left as T.untyped for now so that we can slowly
      # roll out a typed interface.
      #
      # actor - A Team or User to grant or revoke a role for.
      # target - A Repository, Organization or Business grant a role on.
      # role - A Role to be granted.
      # grantor - The actor granting the role.
      # conditions - A UserRoleCondition to be used for the grant.
      sig do
        params(
          actor: T.untyped,
          target: T.untyped,
          role: T.untyped,
          grantor: T.untyped,
          conditions: T.nilable(UserRoleCondition)
        ).void
      end
      def initialize(actor:, target: nil, role: nil, grantor: nil, conditions: nil)
        if role.present?
          raise ArgumentError.new("Must pass a valid Role") unless role.kind_of?(Role)

          if target_owner_must_be_organization?(role, target) && !target.owner.organization?
            raise ArgumentError.new("Owner must be an Organization")
          end

          raise ArgumentError.new("Owner must be an Enterprise") if role.kind_of?(EnterpriseRole) && !target.business?
        end

        @actor = actor
        @target = target
        @target_type = target&.user_role_target_type
        @role = role
        @grantor = grantor
        @conditions = conditions
      end

      # Internal: Revoke all roles for actors and targets.
      def self.bulk_revoke(role: nil, actor_type:, actor_ids:, target_type:, target_ids:)
        tag_result = "result:fail"
        if role.present?
          begin
            roles = UserRole.where(role: role, actor_type:, actor_id: actor_ids, target_type:, target_id: target_ids)
            roles.in_batches(of: BATCH_SIZE) do |batch|
              batch.destroy_all
            end
            tag_result = "result:success"
          ensure
            GitHub.dogstats.increment("user_roles.revoked", tags: ["role_name:#{role.name}", tag_result, "actor_type:#{actor_type}", "target_type:#{target_type}", bulk: true])
          end
        else
          begin
            start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            revoked_role_count = UserRole.where(actor_type:, actor_id: actor_ids, target_type:, target_id: target_ids).count
            roles = UserRole.where(actor_type:, actor_id: actor_ids, target_type:, target_id: target_ids)
            roles.in_batches(of: BATCH_SIZE) do |batch|
              batch.destroy_all
            end
            tag_result = "result:success"
          ensure
            elapsed = GitHub::Dogstats.duration(start_time) # in ms
            tags =  [tag_result, "actor_type:#{actor_type}", "count:#{revoked_role_count}", "target_type:#{target_type}", bulk: true]
            GitHub.dogstats.distribution("user_role.revoke_all_roles", elapsed, tags: tags)
          end
        end
      end

      # Public: Grants a role for the specified actor on the specified target.
      #
      # Returns a RoleGrantResult.
      # Raises an ArgumentError if required arguments are missing.
      # Raises a GrantFailure if granting was not successful.
      def grant!
        validate_grant!
        result = grant_unless_exists!
        raise GrantFailure.new(result.reason) unless result.success?
        result
      end

      # Public: Revokes a role for the specified actor on the specified target,
      #         if a UserRole exists for the actor on the target.
      #
      # Returns a RoleGrantResult.
      # Raises an ArgumentError if required arguments are missing.
      # Raises a GrantFailure if revoking was not successful.
      def revoke_if_exists!
        raise_unless_args_present!
        result = revoke_user_role_if_exists
        raise GrantFailure.new(result.reason) unless result.success?
        result
      end

      # Public: Grant a role for the specified actor on the specified target,
      #         if a UserRole does not yet exist for the actor on the target.
      #
      # Returns a RoleGrantResult.
      # Raises an ArgumentError if required arguments are missing.
      # Raises a GrantFailure if granting was not successful.
      # Rescues from ActiveRecord::RecordNotUnique and treats it as a success.
      def grant_unless_exists!
        validate_grant!
        begin
          result = grant_user_role_unless_exists
        rescue ActiveRecord::RecordNotUnique
          report_attrs = {
            "code.namespace" => self.class.name,
            "code.function" => "grant_user_role",
            "info.message" => "grant user role record not unique",
            "gh.user.id" => actor.id,
          }
          GitHub.logger.info(report_attrs)
          Failbot.report($!, report_attrs)
          RoleGrantResult.success!
        else
          raise GrantFailure.new(result.reason) unless result.success?
          result
        end
      end

      private

      # Private: Collection of validators for granting a role
      #
      # Returns nothing.
      # Component methods will Raise depending on the error condition
      def validate_grant!
        raise_unless_args_present!
        verify_grantable_role!
        verify_grantable_conditions!
      end

      # Private: Validate that all required arguments for granting a role are set.
      #
      # Returns nothing.
      # Raises ArgumentError if required arguments are missing.
      def raise_unless_args_present!
        raise ArgumentError.new("Missing required arguments: #{missing_args.join(', ')}") if missing_args?
      end

      # Private: Checks to see if all required arguments for granting a role are set.
      #
      # Returns a Boolean.
      def missing_args?
        missing_args.any?
      end

      # Private: The required arguments for granting a role that are missing.
      #
      # Returns an Array[Symbol].
      def missing_args
        missing_args = []
        missing_args << :actor unless actor.present?
        missing_args << :target unless target.present?

        missing_args
      end

      def verify_grantable_role!
        return if role.internal? && verify_target_type!(role, target)

        if role.is_a? RepositoryRole
          verify_not_lower_than_org_default!
        end
      end

      def verify_not_lower_than_org_default!
        return unless target.owner.organization?
        return unless actor.is_a?(User) && target.owner.direct_member?(actor)
        return unless role.present?
        # skip org base role validation for outside collaborators - https://github.com/github/github/pull/205406
        return if grantor.present? && !target.owner.member?(grantor)

        target_role_name =
          if role.custom?
            role.base_role.name
          else
            role.name
          end

        default_perm = target.owner.default_repository_permission

        if !RepositoryRole.target_greater_than_or_equal_to_other_role?(target: target_role_name, other_role: default_perm)
          raise GrantFailure.new("Invalid role. You cannot assign members a role with lower permission level than the base repository role #{default_perm}.")
        end
      end

      def verify_target_type!(role, target)
        # not all internal roles have their target_type set up
        expected_target = UserRole::INTERNAL_ROLE_TARGET_TYPE[role.name.to_sym] || role.target_type

        unless expected_target
          raise GrantFailure.new("Invalid role. Role doesn't define it, target type must be defined in UserRole::INTERNAL_ROLE_TARGET_TYPE.")
        end

        return true if target.user_role_target_type == expected_target
        return true if UserRole.requires_conditions_to_be_granted?(role, target)

        raise GrantFailure.new("Invalid role. #{role.name} must be assigned over a #{expected_target}.")
      end

      def verify_grantable_conditions!
        error_message =
          if @conditions.nil? && UserRole.requires_conditions_to_be_granted?(role, target)
            "Invalid conditions. Conditions are required to be set."
          elsif @conditions.present? && !(target.is_a?(Business) && target.erp_feature_enabled?(:enterprise_teams_esm))
            "Invalid conditions. Conditions are not permitted to be set on this target."
          end

        raise GrantFailure.new(error_message) if error_message.present?

        return if @conditions.nil?
        return if !@conditions.target_ids.is_a?(Array)

        T.must(@conditions.target_ids).in_groups_of(1000, false) do |ids|
          org_ids = T.cast(target, Business).organizations.where(id: ids).pluck(:id)
          next if ids.difference(org_ids).empty?

          raise GrantFailure.new("Invalid conditions. All organizations must belong to the business.")
        end
      end

      # Private: Loads the existing UserRole for the actor and target.
      #
      # Returns an ActiveRecord::Relation of UserRole.
      def existing_user_role
        @existing_user_role ||=
        if role.present?
          UserRole.where(role: role, actor: actor, target_type: target_type, target_id: target.id)
        else
          UserRole.where(actor: actor, target_type: target_type, target_id: target.id)
        end
      end

      # Private: Grants a role for the specified user on the specified target.
      # Also grants the associated ability record, if there's a base role associated.
      #
      # raises GrantFailure or PermissionTFCARequiredError on permissions error
      # Returns a RoleGrantResult.
      def grant_user_role
        role_name = role.custom? ? "custom_role" : role.name

        # No need to perform the permission granting check twice for roles that
        # have an underlying Ability, as Ability.grant will also do the validation
        actor.can_be_granted_permission_over!(target, role_name) unless ability_grant_required?

        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = "result:fail"

        if ability_grant_required?
          ability_to_grant = BASE_ROLE_TO_ABILITY[role.base_role.name]
          Role.grant_legacy_permissions(actor, ability_to_grant, target, role_name: role.name)
        end

        args = { role: role, actor: actor, target_type: target_type, target_id: target.id }

        if @conditions.present?
          args[:conditions] = @conditions.serialize
        end

        Role.transaction do
          user_role = UserRole.new(args)
          if user_role.save!
            # only emit audit log results for OrganizationRoles and EnterpriseRoles
            # Repository role grants are logged in Repository::MembershipDependency and Team#add_repository
            if role.is_a?(OrganizationRole)
              # Do not instrument the OSM role for ESM on business targets since this is non user facing.
              unless role.security_manager? && Business.user_role_target_type == user_role.target_type
                GitHub.instrument("organization_role.assign", instrument_organization_role_payload)
              end
            elsif role.is_a?(EnterpriseRole)
              GitHub.instrument("enterprise_role.assign", instrument_enterprise_role_payload)
            end
            result = "result:success"
            RoleGrantResult.success!
          else
            RoleGrantResult.failure!(reason: "Failed to grant role: #{role_name} - #{user_role.errors.full_messages.to_sentence}")
          end
        ensure
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          GitHub.dogstats.increment("user_roles.granted", tags: [result, "actor_type:#{actor.class.name}", "role_name:#{role_name}", "target_type:#{target_type}"])
          tags = [result, "actor_type:#{actor.class.name}", "role_name:#{role_name}", "target_type:#{target_type}"]
          GitHub.dogstats.distribution("user_role.grant", (end_time - start_time) * 1_000, tags: tags)
        end
      rescue ::Permissions::Participant::PermissionGrantError
        raise GrantFailure.new($!)
      end

      # Private: Revokes a role for the specified user on the specified target.
      #
      # Returns a RoleGrantResult.
      def revoke_user_role
        if existing_user_role.many?
          revoke_all_user_roles
        else
          revoke_specific_user_role(user_role: existing_user_role.first)
        end
      end

      # Private: Revokes the user_role given as argument
      #
      # returns a RoleGrantResult
      def revoke_specific_user_role(user_role:)
        return RoleGrantResult.success! if user_role.nil?

        result = "result:fail"
        revoked_role = user_role.role
        revoked_role_name = revoked_role.custom? ? "custom_role" : revoked_role.name
        revoked_role_target_type = user_role.target_type

        if user_role.destroy
          if revoked_role.is_a?(OrganizationRole)
            # Do not instrument the OSM role for ESM on business targets since this is non user facing.
            unless revoked_role.security_manager? && Business.user_role_target_type == revoked_role_target_type
              GitHub.instrument("organization_role.revoke", instrument_organization_role_payload(role: revoked_role))
            end
          elsif revoked_role.is_a?(EnterpriseRole)
            GitHub.instrument("enterprise_role.revoke", instrument_enterprise_role_payload(role: revoked_role))
          end
          result = "result:success"
          RoleGrantResult.success!
        else
          RoleGrantResult.failure!(reason: "Failed to revoke role: #{revoked_role_name}")
        end
      ensure
        GitHub.dogstats.increment("user_roles.revoked", tags: ["role_name:#{revoked_role_name}", result, "actor_type:#{actor.class.name}", "target_type:#{target_type}"])
      end

      # Private: Revokes all of the user_roles the actor has on the target
      # The result is consolidated from the result of all the revocations
      #
      # returns a RoleGrantResult
      def revoke_all_user_roles
        return RoleGrantResult.success! if existing_user_role.empty?
        start_time = GitHub::Dogstats.monotonic_time
        revoked_role_count = existing_user_role.count
        tag_result = "result:fail"
        results = []
        existing_user_role.each do |user_role|
          result = revoke_specific_user_role(user_role: user_role)
          if result.success?
            results << nil
          else
            revoked_role_name = user_role.role.custom? ? "custom_role" : user_role.role.name
            results << revoked_role_name
          end
        end
        failed_role_names = results.compact.join(", ")
        if failed_role_names.empty?
          tag_result = "result:success"
          RoleGrantResult.success! if failed_role_names.empty?
        else
          RoleGrantResult.failure!(reason: "Failed to revoke roles: #{failed_role_names}")
        end
      ensure
        elapsed = GitHub::Dogstats.duration(start_time) # in ms
        tags =  [tag_result, "actor_type:#{actor.class.name}", "count:#{revoked_role_count}", "target_type:#{target_type}"]
        GitHub.dogstats.distribution("user_role.revoke_all_roles", elapsed, tags: tags)
      end

      # Private: Revokes a role for the specified user on the specified target,
      #          if the user has already been granted the role.
      #
      #          The returned result will be successful if the user does not
      #          have the role granted, or if revoking the role succeeds. If
      #          revoking the role fails, then the result will be a failure.
      #
      # Returns a RoleGrantResult.
      def revoke_user_role_if_exists
        return RoleGrantResult.success! unless existing_user_role.any?
        revoke_user_role
      end

      # Private: Grants a role for the specified user on the specified target,
      #          if the user has not already been granted the role.
      #
      #          The returned result will be successful if the user already
      #          has the role granted, or if granting the role succeeds. If
      #          granting the role fails, then the result will be a failure.
      #
      # Returns a RoleGrantResult.
      def grant_user_role_unless_exists
        return RoleGrantResult.success! if existing_user_role.any?
        grant_user_role
      end

      # Private: Determines if an ability record needs to be created for the given role and target
      # Returns a boolean
      def ability_grant_required?
        !!(role.base_role && role.is_a?(RepositoryRole))
      end

      def instrument_organization_role_payload(target: self.target, role: self.role, actor: self.actor, conditions: self.conditions)
        payload = {
          organization_role_id: role&.id,
          organization_role_name: role&.name,
          conditions: conditions&.serialize,
        }
        if target.is_a?(Business)
          # For Business targets, we intentionally don't include business information in the payload as these events should be internal-only
        else
          payload[:org] = target
        end

        if actor.is_a?(User)
          payload[:user] = actor
        else
          payload[:team] = actor
        end
        payload
      end

      def instrument_enterprise_role_payload(target: self.target, role: self.role, actor: self.actor, conditions: self.conditions)
        payload = {
          business: target,
          enterprise_role_id: role&.id,
          enterprise_role_name: role&.name,
          conditions: conditions&.serialize,
        }
        if actor.is_a?(User)
          payload[:user] = actor
        else
          payload[:team] = actor
        end
        payload
      end

      def target_owner_must_be_organization?(role, target)
        return false if role.kind_of?(EnterpriseRole)
        return false if role.target_type == "Integration"

        return false if UserRole.requires_conditions_to_be_granted?(role, target)

        !role.preset? || !Role::USER_OWNED_ROLES.include?(role.name)
      end
    end
  end
end
