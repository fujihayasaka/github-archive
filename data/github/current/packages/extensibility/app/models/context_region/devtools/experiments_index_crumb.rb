# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class ExperimentsIndexCrumb < IndexCrumb
      sig { override.returns(String) }
      def label
        "Experiments"
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :devtools_experiments_path
      end
    end
  end
end
