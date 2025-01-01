# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy
      module Positioner
        sig { params(repository: Repository, positions: T::Array[Positions]).returns(Processor::Result) }
        def self.for_positions(repository:, positions:)
          reader = Reader.new(repository:)
          Processor.new(positions:, reader:).call
        end
      end
    end
  end
end
