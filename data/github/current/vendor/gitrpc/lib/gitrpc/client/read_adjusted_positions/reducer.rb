# rubocop:disable Style/FrozenStringLiteralComment
# Internal: This class is responsible for normalizing positioning data so that only a minimal
#   set of data is sent across the wire. Also maps adjusted positions returned from
#   the backend into an array the caller can easily make use of.
module GitRPC
  class Client
    module ReadAdjustedPositions
      # Raised when the mapping for a blob_lookup_data or position is not present
      # in the data returned by the backend
      class MissingPositionError < GitRPC::Error
        def initialize(data)
          @data = data
        end

        attr_reader :data

        def message
          "adjusted position is missing for #{data}"
        end
      end

      # Raised when a non positive integer is passed as an integer
      InvalidPosition = Class.new(GitRPC::Error)

      class Reducer
        include GitRPC::Util

        attr_reader :positioning_data

        # positioning_data - The array of data to be reduced
        # commit_lookup    - A boolean value used by validation to ensure data is homogeneously
        #                    commit based or blob based.
        def initialize(positioning_data, commit_lookup: false, skip_bad: false)
          @positioning_data = positioning_data
          @skip_bad         = skip_bad
          @commit_lookup    = commit_lookup

          partition_data(positioning_data)
        end

        attr_reader :skip_bad
        alias skip_bad? skip_bad

        # Public: reduces the given data to a format expected by the backend.
        #
        # Example:
        # reducer = Reducer.new([[3, oid1, oid2], [9, oid1, oid2]])
        # reducer.reduced_data
        # => [[[3, 9], oid1, oid2]]
        def reduced_data
          group_positions.map do |blob_lookup_data, positions|
            blob_lookup_data.unshift(positions)
          end
        end

        # Internal: returns an array of adjusted positions corresponding to the original
        # data provided by the constructor.
        #
        # adjusted_info - a map of the format expected by the backend
        #
        # Example:
        # reducer = AdjustedPositionsReducer.new([[3, oid1, oid2], [9, oid1, oid2]])
        # reducer.ordered_positions({[oid1, oid2] => { 9 => 22, 3 => 15 } })
        # => [15, 22]
        def ordered_positions(adjusted_info)
          positioning_data.map do |data|
            position, *blob_lookup_data = data.values_at(:position, :source, :destination)

            next find_premapped(data) if !adjusted_info.key?(blob_lookup_data)

            position_mappings = adjusted_info[blob_lookup_data]

            next find_premapped(data) if !position_mappings.key?(position)

            position_mappings[position]
          end
        end

        private

        attr_reader :commit_lookup, :premapped_data, :missing

        # Internal: given the array of unnormalized positioning data, this
        # method converts it to a hash of blob lookup data to lists of positions.
        def group_positions
          grouped_hash = Hash.new { |h, k| h[k] = [] }

          missing.each do |data|
            position = data[:position]
            blob_lookup_data = data.values_at(:source, :destination)
            grouped_hash[blob_lookup_data] << position
          end

          grouped_hash.freeze
        end

        # Internal: Find the adjusted position value for the given data
        # This method is used as a last ditch attempt when the backend
        # does not provide a mapping for the positioning data.

        # Raises MissingPositionError if no value is present for the data requested.
        def find_premapped(data)
          if premapped_data.key?(data)
            return premapped_data[data]
          else
            fail MissingPositionError.new(data)
          end
        end

        # Internal: Iterates through the positioning data and storing trivial
        # responses in `premapped_data` and building an array of data that needs
        # to go to the backend to calculate.
        #
        # Rows which contain matching oids just return their input positions without
        # hitting the back end.
        # When skip_bad is true, invalid data rows are mapped to the :bad key. Otherwise
        # an exception is thrown.
        def partition_data(data)
          @missing = []
          @premapped_data = {}

          data.each do |data_row|
            position, source, destination = data_row.values_at(:position, :source, :destination)
            next unless valid_position?(position, data_row)
            next unless valid_data?(source, data_row)
            next unless valid_data?(destination, data_row)

            next unless different_targets?(data_row)

            @missing << data_row
          end
        end

        def valid_data?(blob_target, row)
          return valid_oid?(blob_target, row) if blob_target.is_a?(String)

          resolve_keys = %i(start_commit_oid end_commit_oid base_commit_oid)

          all_keys = resolve_keys + %i(commit_oid path)
          start_oid, end_oid, base_oid, commit_oid, path = blob_target.values_at(*all_keys)

          if (resolve_keys - blob_target.keys).empty?
            return valid_oid?(start_oid, row) &&
                   valid_oid?(end_oid, row) &&
                   (base_oid.nil? || valid_oid?(base_oid, row)) &&
                   valid_path?(path, row)
          end

          valid_oid?(commit_oid, row) && valid_path?(path, row)
        end

        def different_targets?(data)
          position, source, destination = data.values_at(:position, :source, :destination)
          return true if source != destination
          premapped_data[data] = position
          return false
        end

        def valid_path?(path, data)
          return true unless path.nil?
          return premap_bad(data) if skip_bad?
          fail GitRPC::NoSuchPath, path
        end

        def premap_bad(data)
          premapped_data[data] = :bad
          return false
        end

        def valid_position?(position, data)
          return true if position.is_a?(Integer) && position >= 0
          return premap_bad(data) if skip_bad?
          fail InvalidPosition, "invalid position '#{position}'"
        end

        def valid_oid?(oid, data)
          return true if valid_full_oid?(oid)
          return premap_bad(data) if skip_bad?
          fail InvalidFullOid, "wrong argument type #{oid.inspect} (expected 40c String OID)"
        end
      end
    end
  end
end
