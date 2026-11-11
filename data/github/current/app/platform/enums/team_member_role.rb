# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamMemberRole < Platform::Enums::Base
      description "The possible team member roles; either 'maintainer' or 'member'."

      value "MAINTAINER", "A team maintainer has permission to add and remove team members.", value: "maintainer"
      value "MEMBER", "A team member has no administrative permissions on the team.", value: "member"
    end
  end
end
