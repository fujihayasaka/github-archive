# typed: true
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class ExperimentsIndexCrumb < IndexCrumb
      def label
        "Experiments"
      end

      def path_name
        :devtools_experiments_path
      end
    end
  end
end
