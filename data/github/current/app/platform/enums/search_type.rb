# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SearchType < Platform::Enums::Base
      description "Represents the individual results of a search."

      value "ISSUE", "Returns results matching issues in repositories.", value: "Issues"
      # TODO: needs ObjectType representation value "CODE", "Returns results matching repository contents.", value: "Code"
      value "REPOSITORY", "Returns results matching repositories.", value: "Repositories"
      value "USER", "Returns results matching users and organizations on GitHub.", value: "Users"
      # TODO: needs ObjectType representation value "WIKI", "Returns results matching wikis in repositories.", value: "Wikis"
      value "USER_LOGIN", "Returns results matching users and organizations on GitHub. Faster then a normal search but only searches the `name` and `login` field.", value: "UserLogin" do
        visibility :internal
      end
      value "DISCUSSION", "Returns matching discussions in repositories.", value: "Discussions"
    end
  end
end
