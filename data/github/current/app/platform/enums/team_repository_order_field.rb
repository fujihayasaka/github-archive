# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamRepositoryOrderField < Platform::Enums::Base
      description "Properties by which team repository connections can be ordered."

      value "CREATED_AT", "Order repositories by creation time", value: "created_at"
      value "UPDATED_AT", "Order repositories by update time", value: "updated_at"
      value "PUSHED_AT", "Order repositories by push time", value: "pushed_at"
      value "NAME", "Order repositories by name", value: "name"
      value "PERMISSION", "Order repositories by permission", value: "action"
      value "STARGAZERS", "Order repositories by number of stargazers", value: "watcher_count"
    end
  end
end
