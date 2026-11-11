# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    # Internal: Maximum amount of bytes of blob data to return in a single tree
    # summary call across all blobs. The default value is tuned to just under
    # 1MB of blob data. This should allow tree summary responses to be stored
    # in cache.
    #
    # This value is kept here mostly so it can be stubbed by tests and
    # documented. It is not meant to be changed during normal usage of the
    # library.
    @tree_summary_maximum_data_size = 900 * 1024
    (class << self; attr_accessor :tree_summary_maximum_data_size; end)

    # Public: Fetch every blob recursively.
    rpc_reader :read_tree_summary_recursive
    def read_tree_summary_recursive(commit_id)
      remaining_size = Backend.tree_summary_maximum_data_size
      files = []

      reader = ObjectReader.new(native, limit: @tree_summary_maximum_data_size)

      # Each tree entry has the format:
      # [mode, type, OID, size, path]
      entries = ls_tree(commit_id, recurse: true, show_trees: false, long: true)["entries"].map do |ent|
        _mode, type, oid, size_str, filename = ent
        next nil if type != "blob"

        size = size_str.to_i

        content = ""
        if remaining_size > 0
          obj = reader.object(oid, :contents)
          content = obj[:data][0, remaining_size]
          remaining_size -= content.bytesize
        end

        name_encoding = set_filename_encoding(filename)
        encoding = GitRPC::Encoding.guess_and_tag(content)
        binary = encoding.nil?

        {
          "oid"       => oid,
          "name"      => filename,
          "path"      => filename,
          "content"   => content,
          "size"      => size,
          "truncated" => (content.bytesize < size),
          "binary"    => binary,
          "encoding"  => encoding,
          "name_encoding" => name_encoding
        }
      end.compact
      entries
    rescue GitRPC::CommandFailed => e
      raise GitRPC::ObjectMissing.new(e.err, commit_id)
    ensure
      reader&.close
    end
  end
end
