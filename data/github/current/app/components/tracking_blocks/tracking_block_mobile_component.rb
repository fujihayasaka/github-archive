# typed: true
# frozen_string_literal: true

module TrackingBlocks
  class TrackingBlockMobileComponent < TrackingBlockComponent
    def initialize(**kwargs)
      T.bind(self, T.untyped)
      super
    end
  end
end
