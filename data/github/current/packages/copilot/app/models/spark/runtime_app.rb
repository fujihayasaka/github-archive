# typed: strict
# frozen_string_literal: true

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

    # TODO: Temporary until we get the owner added
    sig { returns(T.nilable(User)) }
    def owner
      user
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

    has_many :runtime_app_deploys, dependent: :destroy

    sig { returns(String) }
    def user_role_target_type
      "Spark::RuntimeApp"
    end

    sig { returns(T.nilable(User)) }
    def target_for_conditional_access
      owner
    end
  end
end
