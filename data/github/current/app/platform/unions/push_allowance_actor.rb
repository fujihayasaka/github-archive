# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PushAllowanceActor < Platform::Unions::Base
      description "Types that can be an actor."

      possible_types(
        Objects::User,
        Objects::Team,
        Objects::App,
      )
    end
  end
end
