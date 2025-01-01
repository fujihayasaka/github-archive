# frozen_string_literal: true
#              



module Vexi
  # GetSegmentResponse is the response returned by the GetSegment method.
  class GetSegmentResponse < GetEntityResponse
    attr_reader :segment

    def initialize(name: "", segment: nil, error: nil)
      super(name: name, entity: segment, error: error)
      @segment =      (segment                    )
    end
  end
end
