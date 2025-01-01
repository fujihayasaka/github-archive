# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamMemberOrderField < Platform::Enums::Base
      description "Properties by which team member connections can be ordered."

      value "LOGIN", "Order team members by login", value: "login"
      value "CREATED_AT", "Order team members by creation time", value: "created_at"
      value "RELEVANCE", "Order team members by relevance to the viewer", value: "rank" do
        visibility :under_development
      end
    end
  end
end
