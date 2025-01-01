# typed: true
# frozen_string_literal: true

module Elastomer::Adapters

  # Reads and iterates over code blobs in a given git repository (Repository or Gist).
  # Will only iterate over modified files if given a base_commit_sha.
  class GitRepositoryCodeIterator
    GITRPC_RETRY_COUNT    = 3
    READ_BLOBS_BATCH_SIZE = 25
    TIMEOUT_IN_SECONDS    = 60.minutes

    attr_reader :git_repo, :base_commit_sha, :timeout, :on_timeout_exceeded

    def initialize(git_repo, base_commit_sha: nil, head_commit_sha: nil, timeout: TIMEOUT_IN_SECONDS, on_timeout_exceeded: nil)
      @git_repo = git_repo
      @base_commit_sha = base_commit_sha
      @head_commit_sha = head_commit_sha
      @timeout = timeout
      @on_timeout_exceeded = on_timeout_exceeded
    end

    # Public: Determines if the iterator will likely have any effect when
    # ran.
    #
    # Returns Boolean.
    def iterable?
      return false unless head_commit_sha?
      return false if modified_files_only? && base_commit_sha == head_commit_sha
      return false if git_repo.respond_to?(:maintenance_disabled?) && git_repo.maintenance_disabled?

      true
    end

    # Public: Fetches the commit data which reflects HEAD on the git repo.
    #
    # Returns a Hash containing the commit data if the commit is found.
    def head_commit
      return unless head_commit_sha?
      return @head_commit if defined?(@head_commit)

      @head_commit = gitrpc(:read_commits, [head_commit_sha]).first
    end

    # Public: Fetches the commit OID which reflects HEAD on the git repo.
    #
    # Returns a String of the commit sha.
    def head_commit_sha
      return @head_commit_sha unless @head_commit_sha.nil?

      begin
        @head_commit_sha = gitrpc(:read_refs)["refs/heads/#{git_repo.default_branch}"]
      rescue ::GitRPC::InvalidRepository
        # This repository disappeared. Setting to NULL_OID will make it seem that there is no head_commit_oid.
        @head_commit_sha = GitHub::NULL_OID
      end
    end

    # Public: Determines if head_commit_sha was found and is not a null OID.
    #
    # Returns a Boolean.
    def head_commit_sha?
      head_commit_sha.present? && head_commit_sha != GitHub::NULL_OID
    end

    # Public: Determines if base_commit_sha was supplied and is not a null OID.
    #
    # Returns a Boolean.
    def base_commit_sha?
      base_commit_sha.present? && base_commit_sha != GitHub::NULL_OID
    end

    # Public: Determines if a we have enough information to to a partial iteration only
    # on modified files.
    #
    # Returns a Boolean.
    def modified_files_only?
      base_commit_sha? && head_commit_sha?
    end

    # Public: Determines the amount of time in seconds since iteration has began.
    #
    # Returns seconds as a Float.
    def elapsed_seconds
      return 0 unless @start
      Time.now - @start
    end

    # Public: Begins code iteration. If `base_commit_sha` is supplied, only modified
    # files between the base commit and head commit will be iterated. Otherwise all
    # files will be iterated. Yields a CodeBlob instance for each matching file.
    #
    #   block - The block with which to yield each CodeBlob instance.
    #
    # Returns this instance of the CodeIterator.
    def each(&block)
      @start = Time.now

      begin
        if modified_files_only?
          iterate_modified_files(&block)
        else
          iterate_all_files(&block)
        end
      rescue ::GitRPC::InvalidRepository
        # The repo has disappeared (potentially while we were using it). Nothing to do here.
      end
    end

    private

    # Private: Iterates over all files in the git_repo yielding a
    # CodeBlob instance for each indexable file in the repo.
    #
    # For blobs which do not exceed the ES Max doc size, the full
    # contents of the blob will also be loaded.
    #
    #   block - The block with which to yield each found CodeBlob.
    def iterate_all_files(&block)
      return unless head_commit

      tree_sha = head_commit["tree"]
      page = T.let(0, Integer)

      while page do
        blobs = {}
        large_blobs = {}

        hash = gitrpc(:read_tree_blobs_by_page, tree_sha, page)
        page = hash["next_page"]

        hash["blobs"].each do |blob|
          mode = blob["mode"].to_s(8)
          next if mode == "160000"  # skip submodule entries

          blob["mode"] = mode

          if blob["size"] > GitHub.es_max_doc_size
            add_entry_to_blobs(blob, large_blobs)
          else
            add_entry_to_blobs(blob, blobs)
          end
        end

        iterate_blobs(blobs, &block)
        iterate_large_blobs(large_blobs, &block)
      end
    end

    # Private: Iterates over modified files between the base commit and
    # current head commit in the git_repo yielding a # CodeBlob instance
    # for each indexable file.
    #
    # The full blob contents for each modified file are loaded regardless
    # of the blob's size.
    #
    #   block - The block with which to yield each found CodeBlob.
    def iterate_modified_files(&block)
      return unless base_commit_sha?

      blobs = {}
      # TODO move this into GitRPC so we can use our helper below
      result = git_repo.rpc.diff_tree(base_commit_sha, head_commit_sha, recurse: true)

      result.each do |meta, path|
        m = /^:\d{6}\s+(\d{6})\s+[a-f\d]{40}\s+([a-f\d]{40})\s+(\w)$/i.match(meta)
        next if m.nil?

        _, mode, oid, flag = m.to_a
        next if mode == "160000"  # skip submodule entries

        case flag
        when "A", "M", "C", "R"
          entry = {
            "name" => path,
            "mode" => mode,
            "oid"  => oid,
          }
          add_entry_to_blobs(entry, blobs)
        when "D"
          entry = {
            "name"    => path,
            "mode"    => mode,
            "oid"     => oid,
            "deleted" => true,
          }
          yield CodeBlob.new(entry)
        end
      end

      iterate_blobs(blobs, &block)
    end

    # Helper method that will add the given entry to the blobs hash. The blobs
    # hash has an array of entries. The reason for this is that an individual
    # blob can appear in multiple tree locations in the git repository. So the
    # we store these various tree locations in the blob hash; later we can
    # retrieve each blob exactly once and then index that blob in the multiple
    # tree locations described by the entries.
    #
    # entry - Entry Hash to add.
    # blobs - Hash of entries keyed by OID.
    #
    # Returns the blobs Hash.
    def add_entry_to_blobs(entry, blobs)
      oid = entry["oid"]
      blobs[oid] ||= Array.new
      blobs[oid] << entry
      blobs
    end

    # Private: Iterate through the hash of _blobs_ information retrieving the actual
    # blob data from the file servers, building CodeBlob instances from
    # those blob hashes, and yielding them to the block.
    #
    #   blobs - Hash of blob entries to fetch.
    #   block - The block with which to yield each CodeBlob instance.
    #
    # Returns this CodeIterator instance.
    def iterate_blobs(blobs)
      blobs.keys.each_slice(READ_BLOBS_BATCH_SIZE) do |blob_shas|
        generate_code_blobs(blob_shas, blobs).each do |code_blob|
          blobs[code_blob.oid].each do |blob_info|
            yield code_blob.update(blob_info)
          end
        end
        indexing_timeout!
      end

      self
    end

    # Private: Given a list of `blob_shas` and tree `blobs`, this method will
    # download the blob data from the file servers.
    #
    # Returns an array of `CodeBlob` instances.
    def generate_code_blobs(blob_shas, blobs)
      code_blobs = gitrpc(:read_blobs, blob_shas).map do |blob|
        cb = CodeBlob.new(blob)
        cb.update(blobs[cb.oid].first)
        cb
      end

      code_blobs
    end

    # Private: Iterate through the hash of _blobs_ information, building CodeBlob
    # instances from those blob hashes, and yielding them to the block.
    #
    # Does not load actual blob data from file servers.
    #
    #   blobs - Hash of blob entries to fetch.
    #   block - The block with which to yield each CodeBlob instance.
    #
    # Returns this CodeIterator instance.
    #
    def iterate_large_blobs(blobs)
      blobs.each_value do |blob_infos|
        blob_infos.each do |blob_info|
          yield CodeBlob.new(blob_info)
        end
      end

      indexing_timeout!
      self
    end

    # Private: Execute a backend-agnostic command against the remote git
    # repository via its SpokesAdapter methods. Use an exponential backoff to
    # retry the command should a network error be encountered.
    #
    # command - The command to execute as a Symbol.
    # args    - The args to be passed to the command.
    #
    # Returns the results of the command.
    #
    def repo_call(command, *args)
      with_gitrpc_retries do
        result = T.let(nil, T.untyped)
        GitHub.cache.disable_write do
          result = git_repo.send(command, *args)
        end
        result
      end
    end

    # Private: Execute a GitRPC command against the remote git repository. Use an
    # exponential backoff to retry the command should a network error be
    # encountered.
    #
    # command - The command to execute as a Symbol.
    # args    - The args to be passed to the command.
    #
    # Returns the results of the command.
    #
    def gitrpc(command, *args)
      with_gitrpc_retries do
        result = T.let(nil, T.untyped)
        git_repo.rpc.cache.disable_write do
          result = git_repo.rpc.send(command, *args)
        end
        result
      end
    end

    def with_gitrpc_retries
      retries = 0

      begin
        yield
      rescue ::GitRPC::NetworkError, ::GitRPC::CommandBusy => boom
        retries += 1
        raise boom if retries > GITRPC_RETRY_COUNT

        sleep((2**retries - 1) / 4.0)  # exponential backoff [0.25, 0.75, 1.75, ...]
        retry
      end
    end

    # Private: If the current elapsed time since iteration began has exceeded the
    # configured timeout limit, calls the specified `on_timeout_exceeded` callback.
    #
    # Useful for raising an exception to bail out of further iteration.
    def indexing_timeout!
      if elapsed_seconds > timeout && on_timeout_exceeded
        on_timeout_exceeded.call
      end
    end

    class CodeBlob
      # DEPRECATED: Stop including BlobHelper mixin
      include Linguist::BlobHelper
      include GitHub::UTF8

      FUNCTION = "Function".freeze
      METHOD   = "Method".freeze
      CLASS    = "Class".freeze
      MODULE   = "Module".freeze

      attr_reader :name
      attr_accessor :oid, :mode, :size, :encoding, :binary, :data, :deleted, :truncated, :symbols
      alias :sha :oid
      alias :path :name
      alias :deleted? :deleted
      alias :truncated? :truncated

      # Add some data massaging to the struct initializer.
      def initialize(hash)
        self.oid       = hash.fetch("oid", nil)
        self.name      = hash.fetch("name", nil)
        self.mode      = hash.fetch("mode", nil)
        self.size      = hash.fetch("size", 0)
        self.encoding  = hash.fetch("encoding", "UTF-8")
        self.binary    = hash.fetch("binary", nil)
        self.data      = hash.fetch("data", nil)
        self.deleted   = hash.fetch("deleted", false)
        self.truncated = hash.fetch("truncated", false)

        transcode_data!
      end

      # Public: Set the name of this name to the given string.
      #
      # str - The name of the blob as a String.
      def name=(str)
        @name = utf8(str.to_s)
        remove_instance_variable :@pathname if defined? @pathname
      end

      # Public: Returns the directory that this blob resides in.
      #
      # Returns a String or nil for top-level files.
      def dirname
        str = pathname.dirname.to_s
        str == "." ? nil : str
      end

      # Public: Returns the base filename without directory.
      #
      # Returns a String or nil if no basename.
      def basename
        str = pathname.basename.to_s
        str.empty? ? nil : str
      end

      # Public: Returns the extension name of this file.
      #
      # Returns a String or nil if no extention.
      def extname
        str = pathname.extname.sub(/\A\./, "")
        str.empty? ? nil : str.downcase
      end

      # Public: Update the `name` and `mode` of the code blob. This allows us
      # to reuse the transcoded data and language identifier and just swap out
      # the name of the file.
      #
      # Returns this CodeBlob
      def update(hash)
        self.name = hash.fetch("name", nil)
        self.mode = hash.fetch("mode", nil)
        self
      end

      # Public: Determine if the blob is indexable. This overrides
      # Linguist::BlogHelper#indexable?
      #
      # Returns true if the blob should be indexed.
      def indexable?
        if data.nil? || data.empty?
          false
        elsif binary
          false
        elsif size > GitHub.es_max_doc_size
          false
        elsif generated?
          false
        else
          true
        end
      end

      # Public: Detects the Language of the blob.
      #
      # Returns a Language or nil if none is detected
      def language
        @language ||= Linguist.detect(self)
      end

      # Public: Determines the language search term.
      #
      # Returns String or nil for unknown languages.
      def language_default_alias
        language.try(:default_alias)
      end

      # Public: Returns the language ID.
      #
      # Returns Integer or nil for unknown languages.
      def language_id
        language.try(:language_id)
      end

      # Public: Returns whether the blob is a dereferenced symlink.  Used
      # by Linguist for language detection.
      #
      # Returns false always.
      def symlink?
        false
      end

      private

      # Internal: Determine if a language object implements the correct interface.
      #
      # Returns truthy if the language implements the required interface.
      def valid_language?
        language && language.respond_to?(:name)
      end

      # Private: helper method used for inferring attributes based on the full path string.
      def pathname
        @pathname ||= Pathname.new(name)
      end

      # Private: Should we try to transcode the data from it's given encoding
      # into the UTF-8 encoding?
      def transcode?
        if data.nil? || data.empty?
          false
        elsif binary
          false
        elsif size > GitHub.es_max_doc_size
          false
        else
          true
        end
      end

      # Private: Attempt to transcode the `data` string from its original
      # encoding into the UTF-8 encoding.
      #
      # This is a two step process. We first try using the encoding passed to
      # us from the ernicorn process running on the file servers. If the
      # transcode method does not know about this encoding it will raise an
      # `ArgumentError`. We swallow that error and just force UTF-8 encoding
      # by stripping out unknown characters from the string.
      #
      # Finally the `encoding` is set to "UTF-8".
      #
      # Returns `self` for chaining.
      def transcode_data!
        unless transcode?
          self.data = nil
          return self
        end

        begin
          self.data = GitHub::Encoding.transcode(data, encoding, "UTF-8")
          self.encoding = "UTF-8"
        rescue ArgumentError
          self.data = GitHub::Encoding.transcode(data, "UTF-8", "UTF-8")
          self.encoding = "UTF-8"
        end

        self
      end
    end

  end
end
