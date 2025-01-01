# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Enums
        class SubjectType < T::Enum
          enums do
            Line = new(:line)
            File = new(:file)
          end

          sig do
            params(
              value: T.nilable(T.any(String, Symbol, SubjectType)),
              default: SubjectType
            ).returns(SubjectType)
          end
          def self.deserialize_with_default(value, default:)
            case value
            when SubjectType then value
            when "line", :line then SubjectType::Line
            when "file", :file then SubjectType::File
            else default
            end
          end

          sig { returns(T::Boolean) }
          def file? = self == File

          sig { returns(T::Boolean) }
          def line? = self == Line
        end

        class Side < T::Enum
          enums do
            Left = new(:left)
            Right = new(:right)
          end

          sig do
            params(
              value: T.nilable(T.any(String, Symbol, Side)),
              default: Side
            ).returns(Side)
          end
          def self.deserialize_with_default(value, default:)
            return value if value&.is_a?(Side)

            # Normalize input to lowercase symbol for comparison
            value = value&.to_s&.strip&.downcase&.to_sym

            case value
            when :left then Side::Left
            when :right then Side::Right
            else default
            end
          end

          sig { returns(T::Boolean) }
          def left? = self == Left

          sig { returns(T::Boolean) }
          def right? = self == Right
        end
      end
    end
  end
end
