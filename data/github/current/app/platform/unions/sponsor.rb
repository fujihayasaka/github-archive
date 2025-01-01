# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Sponsor < Platform::Unions::Base
      description "Entities that can sponsor others via GitHub Sponsors"

      possible_types(
        Objects::User,
        Objects::Organization,
      )
    end
  end
end
