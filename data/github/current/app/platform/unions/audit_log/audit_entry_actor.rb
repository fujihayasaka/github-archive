# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    module AuditLog
      class AuditEntryActor < Platform::Unions::Base
        description "Types that can initiate an audit log event."


        possible_types(
          Objects::Bot,
          Objects::Organization,
          Objects::User,
        )
      end
    end
  end
end
