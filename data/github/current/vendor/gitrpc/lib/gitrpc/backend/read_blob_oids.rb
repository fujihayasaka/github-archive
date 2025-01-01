# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :read_blob_oids
    def read_blob_oids(commits_and_paths, options = {})
      skip_bad = !!options["skip_bad"]

      BlobOIDReader.new(commits_and_paths, rugged, skip_bad: skip_bad).read_oids
    end

    class BlobOIDReader
      def initialize(commits_and_paths, rugged, skip_bad: false)
        @skip_bad          = skip_bad
        @commits_and_paths = commits_and_paths
        @rugged            = rugged
      end

      def read_oids
        commits_and_paths.map do |commit_oid, path|
          next handle_error(GitRPC::NoSuchPath.new("nil path")) if commit_oid.nil? || path.nil?
          begin
            root = fetch_tree(commit_oid)
            entry = root.path(path)

            if entry[:type] != :blob
              next handle_error(GitRPC::InvalidObject.new("path '#{path}' of #{commit_oid} is '#{entry[:type]}' instead of expected blob"))
            end

            entry[:oid]
          rescue Rugged::OdbError => e
            handle_error(GitRPC::ObjectMissing.new(e.message, commit_oid))
          rescue Rugged::TreeError => e
            handle_error(GitRPC::NoSuchPath.new(e))
          rescue Rugged::InvalidError
            handle_error(GitRPC::InvalidObject.new("Invalid commit oid #{commit_oid}"))
          rescue GitRPC::InvalidObject => e
            handle_error(e)
          end
        end
      end

      private

      attr_reader :commits_and_paths, :skip_bad, :rugged
      alias skip_bad? skip_bad

      def handle_error(err)
        if skip_bad?
          nil
        else
          fail err
        end
      end

      # copied near verbatim from read_tree_entries.rb
      def fetch_tree(oid)
        obj = rugged.lookup(oid)
        case obj.type.to_sym
        when :commit
          obj.tree
        when :tree
          obj
        else
          fail GitRPC::InvalidObject, "Invalid object type #{obj.type}, expected commit or tree"
        end
      end
    end
  end
end
