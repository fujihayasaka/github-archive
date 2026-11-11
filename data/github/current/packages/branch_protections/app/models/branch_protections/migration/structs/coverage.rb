# typed: strict
# frozen_string_literal: true

module BranchProtections
  module Migration
    module Structs
      class Coverage < T::Struct
        const :status, CoverageStatus
        const :gaps, T::Array[T.untyped], default: []

        sig { returns(T::Boolean) }
        def full?
          status == CoverageStatus::FullyCovered
        end

        sig { returns(T::Boolean) }
        def partial?
          status == CoverageStatus::PartiallyCovered
        end

        sig { returns(T::Boolean) }
        def none?
          status == CoverageStatus::NotCovered
        end

        sig { returns(T::Boolean) }
        def unknown?
          status == CoverageStatus::Unknown
        end

        sig { returns(Structs::Coverage) }
        def self.full
          Structs::Coverage.new(status: CoverageStatus::FullyCovered)
        end

        sig { params(rule_name: T.nilable(String)).returns(Structs::Coverage) }
        def self.none(rule_name = nil)
          Structs::Coverage.new(
            status: CoverageStatus::NotCovered,
            gaps: [rule_name ? "#{rule_name} is not covered" : "No coverage"],
          )
        end

        sig { params(rule_name: T.nilable(String)).returns(Structs::Coverage) }
        def self.unknown(rule_name = nil)
          Structs::Coverage.new(
            status: CoverageStatus::Unknown,
            gaps: [rule_name ? "#{rule_name} coverage is unknown" : "Unknown coverage"],
          )
        end
      end
    end
  end
end
