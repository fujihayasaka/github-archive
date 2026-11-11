# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class VersionedOperation < OpenApi::Description::Operation

      def initialize(operation, version, schedule: OpenApi::Description::Changeset.schedule, release: nil)
        @operation = operation.deep_dup
        @version   = version
        @schedule  = schedule
        @release   = release

        super(apply_version(@operation))
      end

      def version_applied?
        true
      end

      private

      # Private: Recursively apply breaking changes to the operation and any of its schema.
      #
      # node - The operation, or any of its subschemas (called recursively).
      def apply_version(node)
        case node
        when Hash
          apply_args = {
            api_version: @version,
            changeset_schedule: @schedule || OpenApi::Description::Changeset.schedule,
            scope: :full,
          }
          apply_args[:release] = @release if @release
          OpenApi::Description::BreakingChanges.apply(node, **apply_args)
          node.each { |_k, v| apply_version(v) }
        when Array
          node.each { |v| apply_version(v) }
        else
          node
        end
      end
    end
  end
end
