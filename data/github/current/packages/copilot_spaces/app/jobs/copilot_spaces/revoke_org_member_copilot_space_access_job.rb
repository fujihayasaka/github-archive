# typed: true
# frozen_string_literal: true

module CopilotSpaces
  class RevokeOrgMemberCopilotSpaceAccessJob < BatchedJob
    queue_as :revoke_org_member_copilot_space_access
    retry_on_dirty_exit

    BATCH_SIZE = 100

    sig do
      params(
        args: T.untyped,
        timestamp: Time,
        offset_item_id: Integer,
        progress: Integer,
        options: T.untyped
      ).returns(T.nilable(T::Array[CopilotSpace]))
    end
    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      org = options[:org]
      user = options[:user]

      return [] unless org && user

      org_custom_copilot_ids = CopilotSpace.where(owner: org).where("id > ?", offset_item_id).order(:id).limit(BATCH_SIZE).pluck(:id)
      user_role_custom_copilot_ids = UserRole.where(actor: user, target_id: org_custom_copilot_ids, target_type: "CustomCopilot").pluck(:target_id)
      CopilotSpace.where(id: user_role_custom_copilot_ids).order(:id).to_a
    end

    sig { params(batch: T::Array[CopilotSpace], args: T.untyped, options: T.untyped).void }
    def process_batch(batch, *args, **options)
      user = options[:user]

      return unless user

      batch.each do |copilot_space|
        copilot_space_roles = Role.where(target_type: "CustomCopilot")

        copilot_space_roles.each do |role|
          with_write do
            Permissions::Granters::RoleGranter.new(actor: user, target: copilot_space, role: role).revoke_if_exists!
          end
        end
      end
    end
  end
end
