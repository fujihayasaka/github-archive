# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Requests
        # Request for invalid/unparseable inputs that cannot be processed.
        #
        # == Purpose
        #
        # This is a "null object" request type created when the factory cannot parse
        # the input into a processable form. Common causes:
        # - Positions::Indeterminate (positioning struct couldn't be computed)
        # - Positions::Errored (error during positioning computation)
        # - Missing required fields in the input
        #
        # == Structure
        #
        # Invalid requests have minimal structure:
        # - **input**: The original input that couldn't be processed
        # - **target_range**: The target commit range (for consistency)
        # - **error**: The specific error describing why processing failed
        #
        # == Processing
        #
        # Invalid requests skip the entire positioning pipeline:
        # - No states (empty states array)
        # - No diff hunk needed
        # - to_result immediately returns the error
        #
        # This allows the processor to handle Invalid uniformly with other request
        # types without special-casing nil checks everywhere.
        class Invalid < T::Struct
          const :input, Positioner::Inputs::Types
          const :target_range, Types::CommitRange
          const :error, CommentPosition::Errors

          sig { returns(Types::CommitRange) }
          def source_range = target_range

          sig { returns(T::Array[Locations::State]) }
          def states = []

          sig { returns(T.nilable(Locations::State)) }
          def end_state = nil

          sig { returns(T::Boolean) }
          def needs_diff_hunk? = false

          sig { returns(T.any(Positioner::Result, CommentPosition::Errors)) }
          def to_result = error
        end
      end
    end
  end
end
