# typed: true
# frozen_string_literal: true

module Permissions
  class SystemRoles
    class ReconcileError < StandardError ; end
    attr_accessor :verbose, :dry_run, :purge

    # This library provides the mechanism to reconcile the system roles found in the DB
    # with the system roles defined by configuration.
    def initialize(config)
      @config_fgp = config
    end

    # Public: reconcile the system roles defined by configuration with the
    #         roles currently present in the DB. By default it will add missing
    #         role, fine_grained_permissions, and role_permission records.
    #         Unless specified, it will only remove role records present in the DB
    #         but not defined in configuration.
    #
    # - purge: wether to remove fine_grained_permissions and role_permissions
    #          that are not defined in configuraiton. Boolean, defaults to false.
    #
    # - dry_run: if true, go through the reconciliation without adding/removing records.
    def reconcile(purge: false, dry_run: false, verbose: false)

      @purge = purge
      @dry_run = dry_run
      @verbose = verbose

      log "starting system role reconciliation"
      log "running in dry_run mode" if dry_run
      if purge?
        log "purge flag was enabled, records present in the DB but not in the system config will be removed"
      else
        log "purge flag is disabled, records present in the DB but not in the system config will not be removed"
      end

      ApplicationRecord::Iam.transaction do
        begin
          reconcile_roles
          reconcile_base_roles if base_roles?
          reconcile_role_target_types
          reconcile_role_permissions
        rescue ActiveRecord::RecordInvalid => e
          puts e.inspect
          puts "Rolling back."
          raise ActiveRecord::Rollback
        end
      end
    end

    private

    # Internal: reconcile the role records. Note that the reconciliation of the
    #           base role attribute is done separatedly.
    def reconcile_roles
      roles_to_remove.each do |role|
        if purge?
          log "removing role: #{role.name}"
          role.destroy unless dry_run?
        else
          log "if purge = true, would remove: #{role.name}"
        end
      end

      roles_to_add.each do |role|
        log "adding role: #{role.name}"
        role.save! unless dry_run?
      end
    end

    # Internal: reconcile the base_role attribute of system roles found in the DB to match the configuration.
    #           Depends on reconcile_roles having already been run so dependencies are in place.
    def reconcile_base_roles
      return unless base_roles?

      Role.presets.each do |role|
        system_base_role = system_base_role_for(role.name)

        if role.base_role&.name != system_base_role

          # avoid 1 network jump to the DB if the base role should be nil
          if system_base_role.nil?
            log "updating base role of #{role.name} nil"
            role.update!(base_role_id: nil) unless dry_run?
            next
          end

          log "updating base role of #{role.name} from #{role.base_role&.name} to #{system_base_role}"
          unless dry_run?
            id = Role.presets.find_by!(name: system_base_role).id
            role.update!(base_role_id: id)
          end
        end
      end
    end

    # Internal: Reconcile the target_type attribute of system roles found in the DB to match the configuration.
    #           Depends on reconcile_roles having already been run so dependencies are in place.
    #           Raises an error if trying to change the target_type of a role that already has a target type
    #           because user_roles would also need to be updated and can't be - can't get IDs for new targets.
    #           If you need to change the target_type of an existing role, please contact #authorization for help!
    def reconcile_role_target_types
      Role.presets.each do |role|
        system_target_type = system_target_type_for_role(role.name)

        if role.target_type != system_target_type
          if role.target_type.nil?
            log "setting target_type of #{role.name} to #{system_target_type}"
            role.update!(target_type: system_target_type) unless dry_run?
          else
            raise ReconcileError.new("Cannot change target type of role #{role.name} from #{role.target_type} to #{system_target_type}. Target types cannot be automatically changed once set.")
          end
        end
      end
    end

    # Internal: reconcile the fine_grained_permission and role_permission records in the DB
    #           to match the configuration.
    #           Depends on reconcile_roles having already been run so dependencies are in place.
    def reconcile_role_permissions
      add_missing_role_permissions
      remove_extra_role_permissions
    end

    # Internal: add role_permissions records defined by configuration, but not found in the DB.
    #           Depends on reconcile_roles having already been run
    def add_missing_role_permissions
      Role.presets.each do |role|
        system_role_fgps = system_permissions_for_role(role.name)

        # the role has no FGPs associated with it in the configuration
        next unless system_role_fgps.present?

        missing_fgps = system_role_fgps - role.permissions.map(&:action)

        missing_fgps.each do |fgp_name|
          log "adding FGP #{fgp_name} to role #{role.name}"

          unless dry_run?
            fgp = Permissions::FineGrainedPermissionIm.find(fgp_name)
            if fgp.nil?
              raise ReconcileError.new("FGP '#{fgp_name}' is assigned to a role but not defined. FGPs are defined in config/access_control/fine_grained_permissions/user_fgps")
            end

            RolePermission.create!(role_id: role.id, action: fgp.action)
          end
        end
      end
    end

    # Internal: remove role_permission records which are present in the DB but are not defined in the configuration.
    #           Depends on add_missing_role_permissions having already been run so dependencies are in place.
    def remove_extra_role_permissions
      Role.presets.each do |role|
        system_role_fgps = system_permissions_for_role(role.name)

        if system_role_fgps.nil?
          if purge?
            log "removing all FGPs from role #{role.name}"
            role.permissions.destroy_all unless dry_run?
          else
            log "if purge = true, would remove all FGPs from role: #{role.name}"
          end

          next
        end

        role.permissions.each do |role_permission|
          next if system_role_fgps.include?(role_permission.action)

          if purge?
            log "removing FGP #{role_permission.action} from role #{role.name}"
            role_permission.destroy! unless dry_run?
          else
            log "if purge = true, would remove FGP #{role_permission.action} from role: #{role.name}"
          end
        end

      end
    end

    # Internal: the list of system roles present in the DB, but not present in the configuration file.
    #           Hence to be deleted from the DB.
    #
    # Returns: an Array of Roles
    def roles_to_remove
      db_roles.reject { |role| system_roles.include?(role) }.values
    end

    # Internal: the list of system roles present in the configuration file, but not present in the DB.
    #           Hence to be added to the DB.
    #
    # Returns: an Array of Roles
    def roles_to_add
      system_roles.each_with_object([]) do |system_role_name, result|
        next if db_role_names.include?(system_role_name)

        result << Role.new(name: system_role_name)
      end
    end

    # Internal: the system role names defined by configuration.
    #
    # Returns: an Array of Strings
    def system_roles
      @config_fgp["system_roles"].keys
    end

    # Internal: the system role's base role name defined by configuration.
    #
    #  - role_name: a String
    #
    # Returns: a String
    def system_base_role_for(role_name)
      @config_fgp.dig("system_roles", role_name, "base")
    end

    # Internal: the system role's target type as defined by configuration.
    #
    #  - role_name: a String
    #
    # Returns: a String
    def system_target_type_for_role(role_name)
      @config_fgp.dig("system_roles", role_name, "target_type")
    end

    # Internal: the list of Fine Grained Permissions for a given Role.
    #
    # - role_name: a String
    #
    # Returns an Array of Strings or nil if no role is found
    def system_permissions_for_role(role_name)
      @config_fgp.dig("system_roles", role_name, "permissions")
    end

    # Internal: the list of preset roles currently found in the DB.
    #
    # Returns: a Hash of Roles indexed by the role name.
    def db_roles
      Role.presets.index_by(&:name)
    end

    # Internal: the name of the preset roles currently found in the DB.
    #
    # Returns: an Array of Strings
    def db_role_names
      db_roles.keys
    end

    # Internal: Check if the base_roles migration has been run.
    #
    # Returns a Boolean
    def base_roles?
      Role.has_attribute?(:base_role_id)
    end

    def log(msg)
      puts msg if verbose?
    end

    def purge?
      @purge
    end

    def dry_run?
      @dry_run
    end

    def verbose?
      @verbose
    end
  end
end
