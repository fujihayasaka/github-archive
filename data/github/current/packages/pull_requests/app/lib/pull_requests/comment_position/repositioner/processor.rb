# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Repositioner
      # The pure business logic layer of repositioning locations across various Git graphs. All side effects
      # are delegated out to the ICommand.
      class Processor
        sig do
          params(
            command: ICommand,
            requests: T::Array[Request],
            range: Positions::DiffRange,
          ).void
        end
        def initialize(command:, requests:, range:)
          @command = command
          @requests = requests
          @range = range
        end

        sig { returns(T::Hash[Request, Positions]) }
        def call
          result = T.let({}, T::Hash[Request, Positions])

          # Walk all the requests, reuse the positioning data if it's already up to date. Update the range value so
          # the correct diff range is included in the payload.
          @requests.each do |request|
            if position = request.available_positionings.find { up_to_date?(_1) }
              result[request] = position.clone_with_new_range(range: @range)
            end
          end

          result
        end

        private

        sig { params(position: T.nilable(Positions)).returns(T::Boolean) }
        def up_to_date?(position)
          # Not up to date if it doesn't exist!
          return false if position.nil?

          # If the cached diff range matches what's being queried, we're up to date.
          return true if position.range == @range

          # Determine if the position targets either the left or right side of the diff, even if the other side
          # differs.
          case position
          when Positions::File, Positions::Line
            reusuable_commit?(position.commit_oid, position.range)
          when Positions::Multiline
            reusuable_commit?(position.start_commit_oid, position.range) &&
              reusuable_commit?(position.end_commit_oid, position.range)
          when Positions::Invalid
            false
          else T.absurd(position)
          end
        end

        sig { params(commit_oid: String, position_range: Positions::DiffRange).returns(T::Boolean) }
        def reusuable_commit?(commit_oid, position_range)
          (commit_oid == position_range.start_commit_oid && commit_oid == @range.start_commit_oid) ||
            (commit_oid == position_range.end_commit_oid && commit_oid == @range.end_commit_oid)
        end
      end
    end
  end
end
