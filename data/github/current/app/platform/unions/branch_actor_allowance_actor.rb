# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class BranchActorAllowanceActor < Platform::Unions::Base
      description "Types which can be actors for `BranchActorAllowance` objects."

      possible_types(
        Objects::User,
        Objects::Team,
        Objects::App,
      )
    end
  end
end
