# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Repositioner
      module Logging
        class Commands
          include ICommand

          class Action < T::Struct
            # The name of the action performed.
            const :name, Symbol
            # Optional logging context to inject.
            const :context, T.nilable(String)
            # Which identifier is this action associated with?
            const :identifiers, T::Array[Integer]

            # Enable comparisons, used in tests.
            sig { params(other: T.untyped).returns(T::Boolean) }
            def ==(other)
              case other
              when Action then other.serialize == serialize
              else false
              end
            end

            # Serialize to a single string to be used in a "rollup" logging array.
            sig { returns(String) }
            def to_logging_s
              if context.present?
                "#{name}(#{context})"
              else
                "#{name}"
              end
            end
          end

          sig { returns(T::Array[Action]) }
          attr_reader :actions

          sig { params(delegate: ICommand).void }
          def initialize(delegate:)
            @delegate = delegate
            @actions = T.let([], T::Array[Action])
          end
        end
      end
    end
  end
end
