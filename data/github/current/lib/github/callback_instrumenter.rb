
# typed: true
# frozen_string_literal: true

module GitHub
  module CallbackInstrumenter
    extend T::Helpers

    requires_ancestor { Object }

    def after_commit(*args, **options, &block)
      handler = args.first
      args = args.drop(1) if handler.is_a?(Symbol) || handler.respond_to?(:after_commit)

      super *T.unsafe(args), **T.unsafe(options) do
        instrumentation_enabled = GitHub.flipper[:instrument_rails_callbacks].enabled?
        if instrumentation_enabled
          hook = "after_commit"
          metric = "callbacks.dist.time"
          handler_name = handler.is_a?(Symbol) ? handler : handler.class.name
          tags = ["class:#{self.class.name}", "hook:#{hook}", "handler:#{handler_name}"]
          timer = ::Timer.start
        end

        if block_given?
          instance_exec(&block)
        else
          if handler.is_a?(Symbol)
            send(handler)
          elsif handler.respond_to?(:after_commit)
            handler.after_commit(self)
          end
        end

        if instrumentation_enabled
          timer.stop
          GitHub.dogstats.distribution(metric, timer.elapsed_ms, tags: tags)
        end
      end
    end

    def after_create(*args, **options, &block)
      handler = args.first
      args = args.drop(1) if handler.is_a?(Symbol) || handler.respond_to?(:after_save)

      super *T.unsafe(args), **T.unsafe(options) do
        instrumentation_enabled = GitHub.flipper[:instrument_rails_callbacks].enabled?
        if instrumentation_enabled
          hook = "after_create"
          metric = "callbacks.dist.time"
          handler_name = handler.is_a?(Symbol) ? handler : handler.class.name
          tags = ["class:#{self.class.name}", "hook:#{hook}", "handler:#{handler_name}"]
          timer = ::Timer.start
        end

        if block_given?
          instance_exec(&block)
        else
          if handler.is_a?(Symbol)
            send(handler)
          elsif handler.respond_to?(:after_create)
            handler.after_create(self)
          end
        end

        if instrumentation_enabled
          timer.stop
          GitHub.dogstats.distribution(metric, timer.elapsed_ms, tags: tags)
        end
      end
    end

    def after_save(*args, **options, &block)
      handler = args.first
      args = args.drop(1) if handler.is_a?(Symbol) || handler.respond_to?(:after_save)

      super *T.unsafe(args), **T.unsafe(options) do
        instrumentation_enabled = GitHub.flipper[:instrument_rails_callbacks].enabled?
        if instrumentation_enabled
          hook = "after_save"
          metric = "callbacks.dist.time"
          handler_name = handler.is_a?(Symbol) ? handler : handler.class.name
          tags = ["class:#{self.class.name}", "hook:#{hook}", "handler:#{handler_name}"]
          timer = ::Timer.start
        end

        if block_given?
          instance_exec(&block)
        else
          if handler.is_a?(Symbol)
            send(handler)
          elsif handler.respond_to?(:after_save)
            handler.after_save(self)
          end
        end

        if instrumentation_enabled
          timer.stop
          GitHub.dogstats.distribution(metric, timer.elapsed_ms, tags: tags)
        end
      end
    end
  end
end
