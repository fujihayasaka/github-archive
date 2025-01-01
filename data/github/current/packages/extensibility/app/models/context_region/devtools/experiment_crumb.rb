# typed: true
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class ExperimentCrumb < Crumb
      def label
        object.name
      end

      def parent
        ExperimentsIndexCrumb.new
      end

      def path_name
        :devtools_experiment_path
      end

      def path_args
        [object]
      end
    end
  end
end
