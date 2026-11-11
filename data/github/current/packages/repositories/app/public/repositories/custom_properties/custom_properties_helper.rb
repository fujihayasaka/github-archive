# typed: strict
# frozen_string_literal: true

module Repositories
  module CustomProperties
    module CustomPropertiesHelper
      include Kernel

      extend self

      sig { params(repo: Repository).returns(T.nilable(T::Hash[Symbol, CustomPropertiesCore::PropertyValue])) }
      def repo_custom_properties_hash(repo)
        return unless repo.owner&.organization?

        effective_properties = T.let(repo.custom_properties_effective_values, T::Hash[String, CustomPropertiesCore::PropertyValue])
        effective_properties.compact.transform_keys(&:to_sym)
      end
    end
  end
end
