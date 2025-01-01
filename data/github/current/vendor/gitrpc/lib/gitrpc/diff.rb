# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Diff
    ALGORITHM_DEFAULT           = "vanilla".freeze
    ALGORITHM_IGNORE_WHITESPACE = "ignore-whitespace".freeze

    VALID_DIFF_ALGORITHMS = [
      ALGORITHM_DEFAULT,
      ALGORITHM_IGNORE_WHITESPACE
    ].freeze

    # Raise an InvalidDiffAlgorithm exception if the given
    # algorithm is not a valid diff algorithm.
    def self.ensure_valid_algorithm(algorithm)
      unless VALID_DIFF_ALGORITHMS.include?(algorithm)
        raise GitRPC::InvalidDiffAlgorithm
      end
    end
  end
end

# Require these after GitRPC::Diff is available
require "gitrpc/diff/delta"
require "gitrpc/diff/diff_tree_parser"
require "gitrpc/diff/summary"
require "gitrpc/diff/status_methods"
