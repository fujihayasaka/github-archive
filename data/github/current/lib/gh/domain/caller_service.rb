# typed: strict
# frozen_string_literal: true

module GH
  module Domain
    module CallerService
      extend T::Helpers

      include Scientist

      requires_ancestor { Kernel }

      sig { returns(Symbol) }
      def caller_service
        klass = self.is_a?(Module) ? self : self.class
        class_name = klass.name
        return :unknown unless class_name
        return :unknown unless serviceowners = GitHub.serviceowners # serviceowners is not present in enterprise

        serviceowners.caller_attribution_cache[class_name] ||= begin
          path, _ = Object.const_source_location(class_name)
          calling_path = path&.gsub(/^#{GitHub::AppEnvironment.root}\//, "")
          GitHub.serviceowners&.service_for_path(calling_path) || :unknown
        end
      end
    end
  end
end
