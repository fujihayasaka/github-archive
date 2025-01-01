module API
  module ConnectionWrappers
    class RepositoryPackageReleasesWrapper < Delegator
      # Encode the id of the node and the node's value for the field that
      # sorting is happening for into a cursor.
      #
      # The node's value for this field will be used to generate a WHERE
      # clause when the cursor is specified on a subsequent request to properly
      # paginate.
      def cursor_from_node(node)
        cursor = [node.id]
        cursor << target.order_by_value(node) if target.order_by_condition
        encode(MessagePack.pack(cursor))
      end

      def offset_from_cursor(cursor)
        MessagePack.unpack(decode(cursor))
      end
    end
  end
end
