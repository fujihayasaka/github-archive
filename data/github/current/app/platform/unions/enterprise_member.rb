# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class EnterpriseMember < Platform::Unions::Base
      description "An object that is a member of an enterprise."

      possible_types(
        Objects::User,
        Objects::EnterpriseUserAccount,
      )
    end
  end
end
