# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class LegacyTeamPermission < Platform::Enums::Base
      description "The legacy team permission."
      visibility :internal

      value "ADMIN", "The admin legacy team permission value.", value: "admin"
      value "PUSH", "The push legacy team permission value.", value: "push"
      value "PULL", "The pull legacy team permission value.", value: "pull"
    end
  end
end
