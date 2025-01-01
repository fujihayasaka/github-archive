# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnvironmentPinnedFilterField < Platform::Enums::Base
      description "Properties by which environments connections can be ordered"

      value "ALL", "All environments will be returned.", value: "all"
      value "ONLY", "Only pinned environment will be returned", value: "only"
      value "NONE", "Environments exclude pinned will be returned", value: "none"
    end
  end
end
