# typed: true
# frozen_string_literal: true

module Stratocaster
  class RefType < String
    REPOSITORY = new("repository").freeze
    BRANCH = new("branch").freeze
    TAG = new("tag").freeze
    UNKNOWN = new("unknown").freeze

    def self.from_ref(ref, default: UNKNOWN)
      return new(default) unless ref

      ref =~ /refs\/tags/ ? TAG : BRANCH
    end

    def path_segment
      case self
      when BRANCH then "compare"
      when TAG then "tree"
      end
    end
  end
end
