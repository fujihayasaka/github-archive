# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Closable
      include Platform::Interfaces::Base

      description "An object that can be closed"

      field :closed,
        Boolean,
        description: "Indicates if the object is closed (definition of closed may depend on type)",
        null: false

      def closed
        async_closable.then do |closable|
          next false unless closable.present?
          closable.closed?
        end
      end

      field :closed_at,
        Scalars::DateTime,
        description: "Identifies the date and time when the object was closed.",
        null: true

      def closed_at
        async_closable.then do |closable|
          next unless closable.present?
          closable.closed_at
        end
      end

      field :viewer_can_close,
        Boolean,
        description: "Indicates if the object can be closed by the viewer.",
        null: false

      def viewer_can_close
        async_closable.then do |closable|
          next false unless closable.present?
          closable.async_closable_by?(@context[:viewer])
        end
      end

      field :viewer_can_reopen,
        Boolean,
        description: "Indicates if the object can be reopened by the viewer.",
        null: false

      def viewer_can_reopen
        async_closable.then do |closable|
          next false unless closable.present?
          closable.async_reopenable_by?(@context[:viewer])
        end
      end

      private

      # Private: Gets the closable object that we can call methods on.
      def async_closable
        case @object
        when PullRequest
          @object.async_issue
        else
          Promise.resolve(@object)
        end
      end
    end
  end
end
