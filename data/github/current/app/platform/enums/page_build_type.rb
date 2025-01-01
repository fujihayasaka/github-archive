# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PageBuildType < Platform::Enums::Base
      description "The possible page build types."
      visibility :internal

      value "LEGACY", "The Page builds with Jekyll.", value: "legacy"
      value "WORKFLOW", "The Page builds with a custom workflow.", value: "workflow"
    end
  end
end
