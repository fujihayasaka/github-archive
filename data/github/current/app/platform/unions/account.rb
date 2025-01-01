# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Account < Platform::Unions::Base
      description "Users, organizations, and enterprise accounts."

      possible_types(
        Objects::User,
        Objects::Organization,
        Objects::Enterprise,
        Objects::Bot,
        Objects::Mannequin,
        Objects::ProgrammaticAccessBot,
      )
    end
  end
end
