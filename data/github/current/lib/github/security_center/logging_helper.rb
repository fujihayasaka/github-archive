# typed: true
# frozen_string_literal: true

module GitHub
  module SecurityCenter
    module LoggingHelper
      extend T::Helpers

      abstract!

      module LogMethods
        extend T::Helpers

        abstract!

        requires_ancestor { Kernel } # caller_locations, block_given?

        # Deprecated: Use `log_info`, `log_warn`, or `log_timing` instead.
        def log(*args, **kwargs, &block)
          fn = kwargs[:"code.function"] || kwargs[:fn] || caller_locations(1, 1)&.first&.base_label # Auto-detect the method that called #log

          log_warn("Detected usage of deprecated logging method", "code.function": fn)

          if block_given?
            log_timing(*T.unsafe(args), "code.function": fn, **kwargs, &block)
          else
            log_info(*T.unsafe(args), "code.function": fn, **kwargs)
          end
        end

        [:info, :warn].each do |level|
          # Same as calling `GitHub.logger.<level>`, but it automatically includes:
          # - `code.function`
          # - `gh.request_id` if present in `GitHub.context`
          # - `gh.request.controller` if present in `GitHub.context`
          # - `gh.request.action` if present in `GitHub.context`
          define_method("log_#{level}") do |*args, **kwargs|
            fn = kwargs[:"code.function"] || kwargs[:fn] || caller_locations(1, 1)&.first&.base_label # Auto-detect the method that called #log
            kwargs = {
              "code.function": fn,
              "gh.request_id": GitHub.context[:request_id],
              "gh.request.action": GitHub.context[:controller_action],
              "gh.request.controller": GitHub.context[:controller],
              **kwargs,
            }

            GitHub.logger.send(level, *args, **kwargs) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          end
        end

        # Logs the start and end of a block including the elapsed time to run the block as `gh.security_center.elapsed_ms`.
        # Sets the provided `step` as `gh.security_center.step` in the logging context of the block.
        # Accepts a variable number of keyword arguments to be logged in the start/end logs.
        #
        # Example:
        #   log_timing(step: "My block", my_attr: "value" ) do
        #     log_info("Hello")
        #   end
        #
        # Outputs:
        #   { "gh.security_center.step": "My block", Body: "Block start", my_attr: "value" }
        #   { "gh.security_center.step": "My block", Body: "Hello" }
        #   { "gh.security_center.step": "My block", Body: "Block end", my_attr: "value", "gh.security_center.elapsed_ms": 2 }
        def log_timing(step:, **kwargs)
          fn = kwargs[:"code.function"] || kwargs[:fn] || caller_locations(1, 1)&.first&.base_label # Auto-detect the method that called #log

          GitHub.logger.with_named_tags("gh.security_center.step": step) do
            log_info(
              "Block start",
              "code.function": fn,
              **kwargs,
            )

            timer = ::Timer.start
            result = yield
            timer.stop

            log_info(
              "Block end",
              "code.function": fn,
              "gh.security_center.elapsed_ms": timer.elapsed_ms,
              **kwargs,
            )

            result
          end
        end
      end

      module WrappingMethods
        extend T::Helpers
        extend T::Sig

        abstract!

        requires_ancestor { LogMethods } # log_timing
        requires_ancestor { Module } # const_get, const_set, etc

        # Accepts a variable number of method names as symbols to wrap with a call to '#log_timing'.
        sig { params(ms: Symbol).void }
        def instrument_method(*ms)
          wrap_methods = ->(methods, const_sym, prepend_receiver) do
            return if methods.blank?
            unless const_defined?(const_sym, false)
              # Create a module to store the wrapped methods so we can prepend it to the receiver
              const_set(const_sym, Module.new)
              prepend_receiver.prepend const_get(const_sym)
            end

            # Add wrapped method to module
            const_get(const_sym).module_eval do
              methods.each do |m|
                # TODO: Maintain the original method's visibility
                define_method(m) do |*args, **kwargs, &block|
                  # We need to override 'code.function' rather than relying on the "auto-detection" in #log
                  # because it incorrectly identifies #instrument_method as the caller of #log_timing.
                  fn = T.must(__method__)
                  class_name = method(fn).super_method&.owner

                  log_timing("code.function": fn, "code.namespace": class_name, step: "Wrapped method execution") { super(*args, **kwargs, &block) }
                end
              end
            end
          end

          # TODO: Figure out if there's a way to identify if the receiver is a class or instance method
          # so we don't wrap both if they share the same name.

          instance_ms = (instance_methods(true) + private_instance_methods(true)).select { |m| ms.include?(m) }
          wrap_methods.call(instance_ms, :LogWrappedInstanceMethods, self)

          class_ms = (methods(true) + private_methods(true)).select { |m| ms.include?(m) }
          wrap_methods.call(class_ms, :LogWrappedClassMethods, singleton_class)
        end
      end

      include LogMethods
      mixes_in_class_methods(LogMethods, WrappingMethods)
    end
  end
end
