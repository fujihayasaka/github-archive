# typed: false
# frozen_string_literal: true

module Billing::Zuora::Webhooks::Callbacks
  extend ActiveSupport::Concern

  prepended do
    include ActiveSupport::Callbacks

    T.unsafe(self).define_callbacks :perform, skip_after_callbacks_if_terminated: true

    class << self
      def before_perform(*args, &block)
        add_callback(:before, *args, &block)
      end

      def after_perform(*args, &block)
        add_callback(:after, *args, &block)
      end

      def around_perform(*args, &block)
        add_callback(:around, *args, &block)
      end

      private

      def add_callback(kind, *args, &block)
        options = args.extract_options!
        options.assert_valid_keys :if, :unless, :only, :except
        T.unsafe(self).set_callback(*[:perform, kind, args, normalize_callback_options!(options)].flatten, &block)
      end

      def normalize_callback_options!(options)
        normalize_callback_option! options, :only, :if
        normalize_callback_option! options, :except, :unless
        options
      end

      def normalize_callback_option!(options, from, to)
        if (from = options.delete(from))
          options[to] = Array(options[to]).unshift(from)
        end
      end
    end
  end

  sig { returns(T::Boolean) }
  def perform
    T.unsafe(self).run_callbacks :perform do
      super
      true
    end
  end
end
