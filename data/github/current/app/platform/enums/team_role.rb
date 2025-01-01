# typed: true
# frozen_string_literal: true
module Platform
  module Enums
    class TeamRole < Platform::Enums::Base
      description "The role of a user on a team."

      value "ADMIN", "User has admin rights on the team.", value: :admin
      value "MEMBER", "User is a member of the team.", value: :member
    end
  end
end
