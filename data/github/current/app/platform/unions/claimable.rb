# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Claimable < Platform::Unions::Base
      docs_category :users
      description "An object which can have its data claimed or claim data from another."

      possible_types(
        Objects::User,
        Objects::Mannequin,
      )
    end
  end
end
