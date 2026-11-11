# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Codeowners < Platform::Unions::Base
      description "Codeowners as defined by CODEOWNERS file"
      possible_types(
        Objects::User,
        Objects::Team,
      )
    end
  end
end
