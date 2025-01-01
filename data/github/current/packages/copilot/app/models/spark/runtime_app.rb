# typed: strict
# frozen_string_literal: true

##
### Specifies the model for the table `runtime_apps` from `copilot-structure.sql`
##

module Spark
  class RuntimeApp < ApplicationRecord::Copilot
    include Permissions::Attributes::Wrapper
    self.permissions_wrapper_class = Permissions::Attributes::RuntimeApp

    self.table_name = "runtime_apps"

    sig { returns(String) }
    def self.generate_random_name
      uuid = SecureRandom.uuid
      digest = Digest::SHA256.hexdigest(uuid)
      T.must(digest[..19])
    end

    sig { returns(Spark::RuntimeAppOwner) }
    def runtime_app_owner
      id = owner_id || user_id
      owner = Spark::RuntimeAppOwner.find_by(owner_id: id)
      owner = SparkRuntime::AppOwner.ensure_owner(T.must(self.user)) if owner.nil?
      owner
    end

    belongs_to :user, optional: false
    validates :permanent_name, presence: true, uniqueness: true, length: { maximum: 20 }
    validates :description, length: { maximum: 255 }
    validates :friendly_name, length: { maximum: 20 }, uniqueness: { scope: :user_id }

    enum :visibility, {
      only_owner: 0,
      github: 1,
      selected_users: 2,
      selected_orgs: 3,
    }
    belongs_to :visibility_organization, class_name: "Organization", optional: true

    has_many :runtime_app_deploys, dependent: :destroy

    sig { returns(String) }
    def user_role_target_type
      "Spark::RuntimeApp"
    end

    sig { returns(T.nilable(User)) }
    def target_for_conditional_access
      runtime_app_owner.owner
    end
  end
end
