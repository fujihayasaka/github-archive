# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class StarOrderField < Platform::Enums::Base
      description "Properties by which star connections can be ordered."

      value "STARRED_AT", "Allows ordering a list of stars by when they were created.",
        value: "created_at"
      value "PUSHED_AT", "Allows ordering a list of stars by recent commits in the repository.",
        value: "pushed_at" do
          visibility :under_development
        end
      value "STARS", "Allows ordering a list of starred repositories by how many stars they have.",
        value: "watcher_count" do
          visibility :under_development
        end
    end
  end
end
