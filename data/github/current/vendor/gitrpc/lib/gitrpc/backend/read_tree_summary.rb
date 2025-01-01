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
    (class <<self; attr_accessor :tree_summary_maximum_data_size; end)

    # Public: Fetch every blob recursively.
    rpc_reader :read_tree_summary_recursive
    def read_tree_summary_recursive(commit_id)
      remaining_size = Backend.tree_summary_maximum_data_size
      files = []

      rugged.lookup(commit_id).tree.walk_blobs do |root, blob|
        filename = root.b + blob[:name].b

        file, remaining_size = build_file(remaining_size, filename, blob)
        files << file
      end

      files
    rescue Rugged::OdbError, Rugged::TreeError => boom
      raise GitRPC::ObjectMissing.new(boom.message, commit_id)
    end

    def build_file(remaining_size, filename, blob)
      oid = blob[:oid]

      blob = rugged.lookup(oid)
      size = blob.size
      content = blob.content
      name_encoding = "UTF-8"

      if remaining_size > 0
        content.force_encoding("binary")
        content = content[0, remaining_size]
        remaining_size -= content.bytesize
      else
        content = +""
      end

      name_encoding = set_filename_encoding(filename)
      encoding = GitRPC::Encoding.guess_and_tag(content)
      binary = encoding.nil?

      file = {
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

      [file, remaining_size]
    end
  end
end
