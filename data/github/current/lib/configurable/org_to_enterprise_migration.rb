# typed: strict
# frozen_string_literal: true

module Configurable
  module OrgToEnterpriseMigration
    extend T::Helpers

    requires_ancestor { Configurable }
    requires_ancestor { ActiveRecord::Base }

    ELIGIBILITY_KEY = T.let("org_to_enterprise_migration.email_notify_eligibility".freeze, String)

    sig { params(actor: User, value: String).returns(T::Boolean) }
    def set_email_notify_eligibility(actor:, value:)
      config.set(ELIGIBILITY_KEY, value, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def clear_email_notify_eligibility(actor:)
      config.delete(ELIGIBILITY_KEY, actor)
    end

    sig { returns(T.nilable(String)) }
    def get_email_notify_eligibility
      config.get(ELIGIBILITY_KEY)
    end
  end
end
