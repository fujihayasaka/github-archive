# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positions
      module Parser
        # Parses positioning data into typed Position objects by combining multiple hash arguments with the first taking precedence.
        sig do
          params(
            input: T.nilable(T.any(String, T::Hash[T.untyped, T.untyped], Positions)),
            base_commit_oid: T.nilable(String),
            head_commit_oid: T.nilable(String),
          ).returns(T.any(Positions, Errors))
        end
        def self.parse(input, base_commit_oid: nil, head_commit_oid: nil)
          positioning = case input
          when Positions
            # This is already a valid position, return it.
            return input
          when String
            begin
              # Attempt to parse the JSON.
              MultiJson.load(input, symbolize_keys: true)
            rescue => exception
              # If we fail to parse, return a parameter error.
              return Errors::Parameter.new(positioning: "must be valid json")
            end
          when Hash, HashWithIndifferentAccess
            input.symbolize_keys
          end

          return Errors::Parameter.new(positioning: "must be valid json") unless positioning.is_a?(Hash)
          return Errors::Parameter.new(positioning: "must be valid json") if positioning.blank?

          base_commit_oid = positioning[:base_commit_oid] ||= base_commit_oid

          unless base_commit_oid.is_a?(String) && GitRPC::Util.valid_full_oid?(base_commit_oid)
            return Errors::Parameter.new(base_commit_oid: "not valid commit oid")
          end

          head_commit_oid = positioning[:head_commit_oid] ||= head_commit_oid

          unless head_commit_oid.is_a?(String) && GitRPC::Util.valid_full_oid?(head_commit_oid)
            return Errors::Parameter.new(head_commit_oid: "not valid commit oid")
          end

          # Delegate the parsing to the respective position type.
          begin
            case type = positioning[:type].to_s.downcase
            when "file"          then Positions::File.parse(positioning)
            when "line"          then Positions::Line.parse(positioning)
            when "multiline"     then Positions::Multiline.parse(positioning)
            when "indeterminate" then Positions::Indeterminate.parse(positioning)
            when "errored"       then Positions::Errored.new(exception: nil, base_commit_oid:, head_commit_oid:)
            else
              Errors::Parameter.new(positioning: "unsupported type: #{type}")
            end
          rescue ArgumentError, TypeError => exception
            Errors::Parameter.new(positioning:)
          end
        end

        sig do
          params(
            input: T.nilable(T.any(String, T::Hash[T.untyped, T.untyped], Positions)),
            base_commit_oid: T.nilable(String),
            head_commit_oid: T.nilable(String),
          ).returns(T.nilable(Positions))
        end
        def self.parse_or_nil(input, base_commit_oid: nil, head_commit_oid: nil)
          case result = T.unsafe(self).parse(input, base_commit_oid:, head_commit_oid:)
          when CommentPosition::Errors then nil
          else result
          end
        end
      end
    end
  end
end
