# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    def merge_single_file(ancestor, ours, theirs, options = {})
      # if the file was created in both branches, we might not have been
      # passed an ancestor, so we'll just stub that out here...
      a = ancestor || {
        :path => nil,
        :oid => nil,
        :filemode => nil
      }

      digest = ::Digest::SHA256.hexdigest([
        a[:path],        a[:oid],        a[:filemode],
        ours[:path],     ours[:oid],     ours[:filemode],
        theirs[:path],   theirs[:oid],   theirs[:filemode],
        options[:our_label], options[:their_label],
      ].join(":"))

      cache_fetch("merge_single_file:v1:#{digest}", backend_method: :merge_single_file) do
        send_message(:merge_single_file, ancestor, ours, theirs, **options)
      end
    end
  end
end
