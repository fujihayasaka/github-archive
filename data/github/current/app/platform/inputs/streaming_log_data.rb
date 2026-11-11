# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class StreamingLogData < Platform::Inputs::Base
      docs_category :meta
      description "Streaming log metadata."

      argument :url, Scalars::URI, "The streaming log url.", required: true
    end
  end
end
