# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.
# This makes sure the boot time of our seeds stays low.

module Seeds
  module Objects
    class Role
      def self.create(owner:, name: "role-#{::Role.last.id + 1}", target_type: "Repository", description: Faker::Lorem.sentence, permissions: [], base_role: "read")
        role = ::Role.find_by(name: name, owner_id: owner.id, owner_type: owner.class.name)
        unless role.present?
          role =
          if target_type == "Repository"
            base_role = Platform::Loaders::Permissions::PresetRole.load(name: base_role).sync
            ::Role.new(name: name, owner_id: owner.id, owner_type: owner.class.name, target_type: target_type, description: description, base_role: base_role)
          elsif target_type == "Organization"
            ::Role.new(name: name, owner_id: owner.id, owner_type: owner.class.name, target_type: target_type, description: description)
          elsif target_type == "Business"
            ::Role.new(name: name, owner_id: owner.id, owner_type: owner.class.name, target_type: target_type, description: description)
          else
            raise ArgumentError, "Target Type #{target_type} is not valid."
          end
          role.save
        end

        permissions = Permissions::FineGrainedPermissionIm.where(actions: permissions)
        permissions.each do |fgp|
          next if RolePermission.find_by(role_id: role.id, action: fgp.action)
          ::RolePermission.new(role_id: role.id, action: fgp.action).save!
        end

        role
      end
    end
  end
end
