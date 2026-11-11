# typed: true
# frozen_string_literal: true

require "prelude"

module GitHub
  module BatchMethod
    extend ActiveSupport::Concern
    extend T::Helpers

    include Prelude::Preloadable

    module ClassMethods
      include Kernel

      def prelude_return_types
        @prelude_return_types ||= {}
      end

      def batch_method(name, return_type = nil, &block)
        prelude_return_types[name] = return_type

        T.bind(self, Prelude::Preloadable::ClassMethods)

        define_prelude(name, &block)

        T.bind(self, Module).define_method("async_batch_#{name}") do |*args|
          T.bind(self, Prelude::Preloadable)

          key = [name, args]
          if preloaded_values.key?(key)
            Promise.resolve(preloaded_values[key])
          else
            # Using T.unsafe here because of the Splat parameter in the load method
            # https://sorbet.org/docs/error-reference#7019
            T.unsafe(Platform::Loaders::Prelude).load(self, name, *args)
          end
        end
      end
    end

    mixes_in_class_methods(ClassMethods)

    # Preload the value for a batch method, bypassing the usual logic for that
    # method. This is not generally safe without additional checks to ensure the
    # value being preloaded is an appropriate return value for the batch method.
    def unsafe_preload_batch_method_value(name, *args, value)
      set_preloaded_value_for(name, args, value)
    end

    # Clear out any preloaded values for a batch method.
    def clear_preloaded_batch_method_value(name, *args)
      preloaded_values.delete([name, args])
    end

    # Clear out preloaded values for all batch methods.
    def reset_batch_methods
      preloaded_values.clear
    end
  end
end
