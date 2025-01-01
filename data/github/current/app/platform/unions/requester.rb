# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Requester < Platform::Unions::Base
      description "An object who can execute GraphQL queries"

      possible_types(
        Objects::RequestingUser,
      )
    end
  end
end
