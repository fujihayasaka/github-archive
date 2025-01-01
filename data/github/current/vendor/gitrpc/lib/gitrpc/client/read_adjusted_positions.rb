# frozen_string_literal: true

require_relative "read_adjusted_positions/reducer"

module GitRPC
  class Client
    # Public: Given a set of positioning information, returns a corresponding set of
    #   adjusted_positions.
    #
    # Example:
    #
    # Given the diff described for read_adjusted_positions
    #
    # diff --git a/sample b/sample
    # index 8422d40..194bca4 100644
    # --- a/sample
    # +++ b/sample
    # @@ -1,4 +1,5 @@
    #  A
    #  B
    #  C
    # +C.2
    #  D
    #
    # path1 = path2 = "sample"
    #
    # read_commit_adjusted_positions(
    #   [
    #     {
    #       position: 3,
    #       source: {
    #         start_commit_oid: commit1_oid,
    #         end_commit_oid:   commit2_oid,
    #         base_commit_oid:  commit1_oid,
    #         path:             path1
    #       },
    #       destination: {
    #         start_commit_oid: commit1_oid,
    #         end_commit_oid:   commit2_oid,
    #         base_commit_oid:  commit1_oid,
    #         path:             path2
    #       }
    #     },
    #     {
    #       position: 1,
    #       source: {
    #         commit_oid: abc1,
    #         path:       path1
    #       },
    #       destination: {
    #         commit_oid: abc2,
    #         path: path2
    #       }
    #     }
    #     ...
    #   ])
    #
    # => [4, 1]
    #
    # Parameters:
    # positioning_data - array of hashes, each matching the signature of `read_commit_adjusted_position`.
    #
    # Returns an array of Integer, nils, or :bad equal in length to the `position_data` array.
    def read_commit_adjusted_positions_with_base(positioning_data, skip_bad: false)
      reducer = ReadAdjustedPositions::Reducer.new(positioning_data, skip_bad: skip_bad)
      options = { "skip_bad" => skip_bad }
      reduced = reducer.reduced_data
      if reduced.empty?
        reducer.ordered_positions({})
      else
        adjusted_info = send_message(:read_adjusted_positions, reduced, options)
        reducer.ordered_positions(adjusted_info)
      end
    end
  end
end
