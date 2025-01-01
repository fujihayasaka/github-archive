# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class IndexCrumb < Crumb
      sig { override.returns(Crumb) }
      def parent
        DevtoolsCrumb.new
      end
    end
  end
end
