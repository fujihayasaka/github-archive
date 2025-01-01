# typed: strict
# frozen_string_literal: true

##
### Specifies the model for the table `runtime_app_owners` from `copilot-structure.sql`
### Tests are in `packages/copilot/test/models/spark/runtime_app_owner_test.rb`
##

module Spark
  class RuntimeAppOwner < ApplicationRecord::Copilot
    self.table_name = "runtime_app_owners"

    validates :permanent_name, presence: true, uniqueness: true, length: { maximum: 20 }
    validates :last_seen_login, presence: true, length: { maximum: 255 }
    validates :deploy_login, presence: true, length: { maximum: 20 }

    # At a schema level, deploy_login allows duplicates.
    # By our model, we can have one instance of any given deploy_login in
    # the segregated and non-segregated groups. i.e. a non-compliant username
    # must mangle to something unique amongst mangled records, while all
    # compliant usernames must be unique within their non-segregated group.
    #
    # This can't be enforced with standard ActiveRecord validations so we do
    # our custom check here.
    validates_each :deploy_login do |record, attr, value|
      if record.is_segregated?
        collision = Spark::RuntimeAppOwner.where(deploy_login: value)
          .where("last_seen_login != deploy_login")
          .where.not(owner_id: record.owner_id)
          .exists?
        record.errors.add(attr, "must be unique within segregated owners") if collision
      else
        collision = Spark::RuntimeAppOwner.where(deploy_login: value)
          .where("last_seen_login = deploy_login")
          .where.not(owner_id: record.owner_id)
          .exists?
        record.errors.add(attr, "must be unique within non-segregated owners") if collision
      end
    end

    belongs_to :owner, class_name: "User", optional: false

    sig { returns(T::Boolean) }
    def is_segregated?
      deploy_login != last_seen_login
    end

    sig { returns(String) }
    def deployment_domain_base
      is_segregated? ? "users.github.app" : "github.app"
    end
  end
end
