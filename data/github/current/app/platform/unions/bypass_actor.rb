# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class BypassActor < Platform::Unions::Base
      docs_category :repos
      description "Types that can represent a repository ruleset bypass actor."

      possible_types(
        Objects::Team,
        Objects::App,
        Objects::User,
        Objects::EnterpriseTeam,
      )
    end
  end
end
