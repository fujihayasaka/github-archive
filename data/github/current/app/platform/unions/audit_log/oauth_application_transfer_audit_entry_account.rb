# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    module AuditLog
      class OauthApplicationTransferAuditEntryAccount < Platform::Unions::Base
        description "Types that can own an OAuth Application."

        visibility :under_development

        possible_types(
          Objects::User,
          Objects::Organization,
        )
      end
    end
  end
end
