# typed: strict
# frozen_string_literal: true

module ContextRegion
  module Devtools
    class ExperimentCrumb < Crumb
      sig { override.returns(String) }
      def label
        object.name
      end

      sig { override.returns(Crumb) }
      def parent
        ExperimentsIndexCrumb.new
      end

      sig { override.returns(T.nilable(Symbol)) }
      def path_name
        :devtools_experiment_path
      end

      sig { override.returns(T::Array[T.untyped]) }
      def path_args
        [object]
      end
    end
  end
end
