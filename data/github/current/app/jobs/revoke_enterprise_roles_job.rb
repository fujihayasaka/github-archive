# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class RevokeEnterpriseRolesJob < ApplicationJob
  queue_as :revoke_enterprise_roles
  retry_on_dirty_exit

  resolve_tenant_context do |business|
    business
  end

  # Public - job to remove all fine-grained permissions from given users
  #
  # business - Business that the users are departing
  # user_ids - list of user ids to perform job on
  sig { params(business_id: Integer, user_ids: T::Array[Integer]).void }
  def perform(business_id:, user_ids: [])
    business = T.let(Business.find_by(id: business_id), T.nilable(Business))
    user_ids = Array(user_ids).compact
    return if user_ids.empty? || business.nil?

    user_ids.each_slice(100) do |user_id_batch|
      # Check if any of these users have custom roles
      users_ids_with_roles = UserRole.where(actor_type: "User", target_type: "Business", target_id: business.id).where(actor_id: user_id_batch).pluck(:actor_id)
      next if users_ids_with_roles.empty?

      users = User.where(id: users_ids_with_roles)
      users.each do |user|
        with_write { Permissions::Granters::RoleGranter.new(actor: user, target: business).revoke_if_exists! }
      end
    end
  end
end
