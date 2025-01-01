# typed: false
# frozen_string_literal: true

module Platform
  module Loaders
    class EntityReference < Platform::Loader
      def self.load(record, batch_method, *args)
        Platform::Loaders::Prelude.for(
          GH::Associations::BatchMethodAdapters.internal_prelude_domain_method_name(batch_method),
          args
        ).load(record)
      end
    end
  end
end
