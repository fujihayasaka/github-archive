# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CheckRunType < Platform::Enums::Base
      description "The possible types of check runs."

      value "ALL", "Every check run available.", value: "all"
      value "LATEST", "The latest check run.", value: "latest"
    end
  end
end
