# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_reader :read_blob_oids
    def read_blob_oids(commits_and_paths, options = {})
      skip_bad = !!options["skip_bad"]

      BlobOIDReader.new(commits_and_paths, rugged, native, skip_bad: skip_bad).read_oids
    end

    rpc_reader :alternative_read_blob_oids
    def alternative_read_blob_oids(commits_and_paths, options = {})
      skip_bad = !!options["skip_bad"]

      BlobOIDReader.new(commits_and_paths, rugged, native, skip_bad: skip_bad, use_git: true).read_oids
    end

    class BlobOIDReader
      def initialize(commits_and_paths, rugged, native, skip_bad: false, use_git: false)
        @skip_bad          = skip_bad
        @commits_and_paths = commits_and_paths
        @rugged            = rugged
        @use_git           = use_git
        @native            = native
      end

      def read_oids
        if @use_git
          read_oids_git
        else
          read_oids_rugged
        end
      end

      def read_oids_git
        rdr = ObjectReader.new(@native)
        commits_and_paths.map do |commit_oid, path|
          next handle_error(GitRPC::NoSuchPath.new("nil path")) if commit_oid.nil? || path.nil?

          cinfo = rdr.object(commit_oid, :info)
          case cinfo[:type]
          when nil
            next handle_error(GitRPC::ObjectMissing.new("object not found - no match for id (#{commit_oid})", commit_oid))
          when :commit, :tree
            # ok, do nothing.
          else
            next handle_error(GitRPC::InvalidObject.new("Invalid object type #{cinfo[:type]}, expected commit or tree"))
          end
          if !GitRPC::Util.valid_full_oid?(cinfo[:oid])
            next handle_error(GitRPC::ObjectMissing.new("object not found - no match for id (#{cinfo[:oid]})", cinfo[:oid]))
          end

          entry = rdr.object([cinfo[:oid], path].join(':'), :info)
          case entry && entry[:type]
          when nil
            handle_error(GitRPC::NoSuchPath.new("the path '#{path}' does not exist in the given tree"))
          when :blob
            entry[:oid]
          else
            handle_error(GitRPC::InvalidObject.new("path '#{path}' of #{commit_oid} is '#{entry[:type]}' instead of expected blob"))
          end
        end
      ensure
        rdr&.close
      end

      def read_oids_rugged
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
