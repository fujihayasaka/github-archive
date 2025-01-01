# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ActorType < Platform::Enums::Base
      description "The actor's type."

      value "USER", "Indicates a user actor."
      value "TEAM", "Indicates a team actor."
    end
  end
end
