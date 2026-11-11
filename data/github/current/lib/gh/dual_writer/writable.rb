# typed: strict
# frozen_string_literal: true

module GH
  class DualWriter
    # Extend this module onto ActiveRecord model classes to enable dual writing.
    #
    # Models must implement two class methods:
    #   - `dual_write_stage`           — returns the current write stage Symbol
    #   - `dual_write_secondary_class` — returns the secondary AR class to write to
    #
    # Because `dual_write_stage` is a method (not a static config value), it can
    # be driven by feature flags, environment checks, or any other runtime logic.
    #
    # Example:
    #
    #   class User < ApplicationRecord
    #     extend GH::DualWriter::Writable
    #
    #     def self.dual_write_stage
    #       if FeatureFlag.vexi.enabled?("role_dual_write", default: false)
    #        GH::DualWriter::WriteStages::BEST_EFFORT
    #       else
    #         GH::DualWriter::WriteStages::TRACK
    #       end
    #     end
    #
    #     def self.dual_write_secondary_class
    #       RoleDestination
    #     end
    #   end
    #
    #   Role.dual_write(:create, role) { role.save! }
    #
    # Models can override `dual_write_handler_for` to add custom operations
    # while calling `super` for defaults:
    #
    #   def self.dual_write_handler_for(operation)
    #     case operation
    #     when :suspend
    #       UserSuspendHandler.new(
    #         secondary_class: dual_write_secondary_class,
    #         stage: dual_write_stage,
    #       )
    #     else
    #       super
    #     end
    #   end
    #
    module Writable
      extend T::Helpers
      abstract!

      sig { abstract.returns(Symbol) }
      def dual_write_stage; end

      sig { abstract.returns(T.class_of(ActiveRecord::Base)) }
      def dual_write_secondary_class; end

      sig { overridable.params(operation: Symbol).returns(Handler) }
      def dual_write_handler_for(operation)
        case operation
        when :create
          Handler::Create.new(secondary_class: dual_write_secondary_class, stage: dual_write_stage)
        else
          Kernel.raise ArgumentError, "Unknown dual write operation: #{operation}"
        end
      end

      sig do
        type_parameters(:T)
          .params(
            operation: Symbol,
            subject: ActiveRecord::Base,
            block: T.proc.returns(T.type_parameter(:T)),
          )
          .returns(T.type_parameter(:T))
      end
      def dual_write(operation, subject, &block)
        DualWriter.track do
          dual_write_handler_for(operation).call(subject, &block)
        end
      end
    end
  end
end
