# typed: strict
# frozen_string_literal: true

module Coders
  class UserCoder < Coders::Base
    # Define a re-usable module for shared data accessors
    # between `UserCoder` and `OrganizationCoder`
    module Shared
      extend T::Helpers
      extend T::Sig
      extend ActiveSupport::Concern

      requires_ancestor { Coders::Base }

      included do
        T.bind(self, T.class_of(Coders::Base))
        data_accessors \
          :deleted,
          :deleted_at,
          :deleted_by,
          :_billing_email,
          :_primary_email,
          :avatar_uuid,
          :gravatar_id,
          :has_used_anonymizing_proxy,
          :needs_ldap_memberships_sync,
          :protocols,
          :raw_login,
          :renamed_at,
          :renaming,
          :repository_navigation_v3_participant,
          :repository_next_participant

        # Define custom overrides. We need to define them _after_ `data_accessors` was called,
        # otherwise they get overridden by the `data_accessors` definitions.

        sig { returns(T.nilable(Time)) }
        def deleted_at
          time(data[:deleted_at])
        end

        sig { returns(T.nilable(Time)) }
        def renamed_at
          time(data[:renamed_at])
        end

        sig { returns(T::Boolean) }
        def empty?
          to_h.empty?
        end

        sig { returns(T::Boolean) }
        def deleted?
          status = data[:deleted]
          status.present? && status != 0
        end
      end
    end

    include Shared
  end
end
