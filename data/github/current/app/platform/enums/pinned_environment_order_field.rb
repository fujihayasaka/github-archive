# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PinnedEnvironmentOrderField < Platform::Enums::Base
      docs_category :deployments
      description "Properties by which pinned environments connections can be ordered"
      value "POSITION", "Order pinned environments by position", value: "position"
    end
  end
end
