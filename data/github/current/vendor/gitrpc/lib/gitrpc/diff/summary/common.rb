# rubocop:disable Style/FrozenStringLiteralComment
module GitRPC
  class Diff
    class Summary
      module Common
        # TODO: this should probably be moved out of GitRPC into
        #       a view helper in the main app instead.
        #
        # Generate a diffstat line that fits within the specified
        # number of columns and using the given symbols.
        def stats(columns = 80, addition_symbol = "+", deletion_symbol = "-")
          adjust = changes > columns ? columns / changes.to_f : 1.0
          (addition_symbol * (additions * adjust)) +
          (deletion_symbol * (deletions * adjust))
        end

        # total lines added or deleted in the diff
        def changes
          additions + deletions
        end
      end
    end
  end
end
