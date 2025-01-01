# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Diffs
      module Contents
        class Params
          include GitHub::Memoizer

          sig { params(paths: String, context: T.nilable(String)).void }
          def initialize(paths:, context:)
            @paths = paths
            @context = context
          end

          sig { returns(T::Array[String]) }
          memoize def paths = @paths.split(",")

          sig { returns(T.nilable(T::Hash[String, T::Array[T::Range[Integer]]])) }
          def context_lines
            return if @context.nil?

            ctx_by_path = @context.split(":")

            paths_with_ranges = paths.zip(ctx_by_path).filter_map do |path, ctx|
              next nil if ctx.nil?
              ranges = ctx.split(",").filter_map { parse_range(_1) }
              [path, ranges] if ranges.any?
            end

            paths_with_ranges.to_h
          end

          private

          sig { params(str: String).returns(T.nilable(T::Range[Integer])) }
          def parse_range(str)
            # We use `Kernel#Integer` instead of `String#to_i` because it is
            # more strict. `String#to_i` will ignore any extra characters
            # after the digits, but `Kernel#Integer` will return `nil` instead.
            first, last = str.split("-", 2).map do |str_part|
              Integer(
                str_part,
                10, # base 10: ignore base indicators like "0xff"
                exception: false,
              )
            end

            return nil if first.nil? || last.nil?
            return nil if first.zero? || last.zero?
            return nil if first >= last

            (first..last)
          end
        end
      end
    end
  end
end
