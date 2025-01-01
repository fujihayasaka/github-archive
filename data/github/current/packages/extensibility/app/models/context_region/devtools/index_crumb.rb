# typed: true
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class IndexCrumb < Crumb
      def parent
        DevtoolsCrumb.new
      end
    end
  end
end
