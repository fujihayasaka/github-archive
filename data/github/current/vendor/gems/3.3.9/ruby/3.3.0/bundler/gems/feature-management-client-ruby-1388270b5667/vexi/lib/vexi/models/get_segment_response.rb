# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"

module Vexi
  # GetSegmentResponse is the response returned by the GetSegment method.
  class GetSegmentResponse < GetEntityResponse
    attr_reader :segment

    def initialize(name: "", segment: nil, error: nil)
      super(name: name, entity: segment, error: error)
      @segment = T.let(segment, T.nilable(Segment))
    end
  end
end
