# typed: strict
# frozen_string_literal: true

# Whether a customer (organization or enterprise account) purchases GitHub products through a reseller
module Configurable
  module ResellerCustomer
    extend T::Sig
    extend T::Helpers

    KEY = T.let("reseller_customer".freeze, String)

    requires_ancestor { Customer }

    sig { params(actor: T.nilable(User)).returns(T::Boolean) }
    def enable_reseller_customer(actor:)
      backup_actor = GitHub.enterprise? ? User.ghost : User.staff_user
      actor ||= User.find_by(id: GitHub.context[:actor_id]) || backup_actor

      config.enable(KEY, actor)
    end

    sig { params(actor: T.nilable(User)).returns(T::Boolean) }
    def disable_reseller_customer(actor:)
      backup_actor = GitHub.enterprise? ? User.ghost : User.staff_user
      actor ||= User.find_by(id: GitHub.context[:actor_id]) || backup_actor

      config.disable(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def reseller_customer?
      return false if new_record?
      config.enabled?(KEY)
    end
  end
end
