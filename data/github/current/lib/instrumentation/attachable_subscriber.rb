# typed: false
# frozen_string_literal: true

module Instrumentation
  module AttachableSubscriber
    extend T::Helpers

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      extend T::Helpers

      def attachable_namespace
        @attachable_namespace
      end

      def set_attachable_namespace(ns)
        @attachable_namespace = ns
      end

      def handle_events(*names)
        names.each do |name|
          send :define_method, name do |started, ended, id, payload|
            handle_event(name, started, ended, id, payload)
          end
        end
      end

      alias handle_event handle_events

      def attach!(subscriber = nil, notifier = nil)
        attach_to attachable_namespace, subscriber, notifier
      end

      def attach_to(namespace, subscriber = nil, notifier = nil)
        subscriber ||= new
        notifier ||= GitHub.instrumentation_service
        subscriber.public_methods(false).each do |event|
          next if "call" == event.to_s

          notifier.subscribe("#{namespace}.#{event}", subscriber)
        end
        subscriber
      end
    end

    # This is crucial for Sorbet to understand that these are class methods
    mixes_in_class_methods ClassMethods

    def call(event, *args)
      method = event.split(".").last
      begin
        send method, *args
      rescue Exception => e # rubocop:todo Lint/RescueException
        Rails.logger.error "Could not log #{event.inspect} event. #{e.class}: #{e.message} #{e.backtrace}"
      end
    end

    private

    if Rails.env.development?
      def handle_event(*args)
        handle_in_development(*args)
      end
    else
      def handle_event(*args)
        handle_in_production(*args)
      end
    end

  end
end
