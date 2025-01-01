# rubocop:disable Style/FrozenStringLiteralComment

require "gitrpc/backend/readers/object_reader"

module GitRPC
  class Backend
    # TZ offsets outside of this range will cause the Time#localtime
    # method to raise an ArgumentError.
    VALID_TZ_OFFSET_RANGE = -86_399..86_399

    # Public: Retrieve a list of commit objects for the given commit oids.
    #
    # oids - Array of oid strings. All oids must be 40 char sha1s.
    #
    # See Client#read_objects for usage documentation.
    def read_commits(oids, read_trailers: nil)
      read_objects(oids, :commit, false, read_trailers: read_trailers)
    end

    # Public: Retrieve a list of blob objects for the given blob oids.
    #
    # oids - Array of oid strings. All oids must be 40 char sha1s.
    #
    # See Client#read_objects for usage documentation.
    def read_blobs(oids)
      read_objects(oids, :blob)
    end

    # Public: Git object reading workhorse method. This method can read any of
    # the core git objects: commit, tree, blob, and tag. Each object must be
    # located, inflated, and converted to the simple object types.
    #
    # oids          - Array of oid strings. All oids must be 40 char sha1s.
    # type          - String object type for validation.
    # skip_bad      - return nil for commits which would have raised errors
    # read_trailers - one of :git, :regexp, or nil to indicate how/if  trailers should
    #                 be parsed. nil means no trailer parsing.
    #
    # Returns an array of simple hashes representing the objects requested.
    # Raises a GitRPC::ObjectMissing exception when any of the requested objects
    # could not be found.
    rpc_reader :read_objects
    def read_objects(oids = [], type = nil, skip_bad = false, read_trailers: nil)
      type = type.to_sym if type

      commits = {}
      # If we only want tree objects, we don't need to parse the data, since
      # we don't use it below.  We do still need to verify that the object
      # really is a tree, though.
      batch_type = if type&.to_sym == :tree
        :info
      else
        :contents
      end
      objects = object_reader(batch_type, oids) do |oid, obj_type, size, data|
        header = {
          type: obj_type&.to_sym,
          len: size,
        }

        if !header[:type]
          if skip_bad
            next
          else
            if oid =~ /\A0+\z/
              raise GitRPC::ObjectMissing.new("odb: cannot read object: null OID cannot exist", oid)
            end
            raise GitRPC::ObjectMissing.new("object not found - cannot read header for (#{oid})", oid)
          end
        end

        if type && header[:type] != type
          if skip_bad
            next
          else
            raise GitRPC::InvalidObject, "Invalid object type #{obj_type}, expected #{type}"
          end
        end

        begin
          object = case header[:type]
          when :commit; parse_commit_object(oid, data, skip_bad: skip_bad, read_trailers: read_trailers)
          when :blob;   parse_blob_object(oid, data, size)
          when :tree;   get_tree_object(oid, header, skip_bad: skip_bad)
          when :tag;    parse_tag_object(oid, data, skip_bad: skip_bad)
          else
            { "oid" => oid, "type" => "unknown" }
          end
        rescue GitRPC::InvalidObject => boom
          if skip_bad
            nil
          else
            if boom.message =~ /Invalid tag object/
              raise
            else
              error = GitRPC::BadObjectState.new(boom.message)
              error.set_backtrace(boom.backtrace)
              raise error
            end
          end
        end

        commits[object["oid"]] = object if read_trailers == :git && header[:type] == :commit

        # sanity check the oid of the object that comes back just to be sure
        # we're not accidentally returning the wrong object.
        if object && oid != object["oid"]
          fail "object oid (#{object['oid']}) does match input oid (#{oid})"
        end

        object
      end.compact

      set_commit_trailers(commits) if read_trailers == :git

      objects
    end

    COMMIT_LINE_MATCHER = /commit\s(#{GitRPC::Util::FULL_OID_REGEXP})/
    GIT_TRAILER_MATCHER = /^(?<key>.+)\:\s(?<value>[^\n]+)\n?/

    # Internal: Sets the "trailers" key of each commit object contained in the commits
    #   hash with a unique hash of trailer keys to lists of their values.
    #
    # commits - a hash of string oids to commit hashes as returned by get_commit_object
    def set_commit_trailers(commits)
      return if commits.empty?

      res = spawn_git("rev-list", ["--stdin", "--no-walk", "--format=%(trailers:only,unfold)"], commits.keys.join("\n"))
      raise ::GitRPC::Error, res["err"] unless res["ok"]

      current_commit = nil
      res["out"].each_line do |line|
        if line =~ COMMIT_LINE_MATCHER
          current_commit = commits[$1]
          current_commit["trailers"] = {}
        elsif match = line.match(GIT_TRAILER_MATCHER)
          next if current_commit.nil?

          key = match["key"].downcase.force_encoding(current_commit["encoding"])
          value = match["value"].force_encoding(current_commit["encoding"])

          current_commit["trailers"][key] ||= []
          current_commit["trailers"][key] << value
        end
      end

      # This is far less than ideal but using a Set for this would mean
      # serialization would blow up later.
      commits.each_value do |commit_hash|
        commit_hash["trailers"].each_value(&:uniq!)
      end
    end

    # This finds the substring of the message containing the trailers but does not
    # identify separate keys and values in that section.
    # NOTE: This confused me, so probably someone else will be confused too at some point.
    # The initial ".*" is greedy so it takes as much of the input as possible, leaving
    # the last batch of trailers if there are multiple sections of trailers delimited by
    # double newlines.
    TRAILER_SECTION_MATCHER = /.*\r?\n\r?\n(\w[^\s]+\:.+)/mn

    # Given the trailer section of a commit message, this identifies the set of keys and
    # values contained within.
    TRAILER_MATCHER = /^(\w[^\s]+)\: (.+?(\r?\n[\t ]+.+?$)*$)/mn

    # Internal: Parse trailers out of the commit message. Trailers are represented as a hash
    #   of keys to arrays of values with matching keys, in order of occurrance in trailers
    #   of message.
    def parse_trailers(message, message_encoding)
      trailers = {}

      return trailers if message.nil?
      return trailers if !message.b.match(TRAILER_SECTION_MATCHER)

      trailer_text = $1
      matches = trailer_text.scan(TRAILER_MATCHER)

      matches.each do |key, value|
        key.force_encoding(message_encoding)
        value.force_encoding(message_encoding)

        key = key.downcase
        trailers[key] ||= []
        trailers[key] << value.split("\n").map(&:strip).join(" ")
      end

      # $' is a special variable containing the "post_match" portion of the string
      # last matched on. We want to make sure there is no text following the trailers
      # that is not itself a trailer. If that is present, then the trailers are not truly trailers
      # and therefore should be thrown away.
      trailers = {} unless $'&.strip&.empty?

      trailers
    end

    # Public: Retrieve a non-truncated blob object for the blob oid.
    #
    # oid - An oid string. Must be 40 char sha1s.
    #
    # See Client#read_large_object for usage documentation.
    rpc_reader :read_full_blob
    def read_full_blob(oid)
      object = {}
      object_reader(:contents, [oid], nil) do |oid, type, size, data|
        if type.nil?
          if oid =~ /\A0+\z/
            raise GitRPC::ObjectMissing.new("odb: cannot read object: null OID cannot exist", oid)
          end
          raise GitRPC::ObjectMissing.new("object not found - cannot read header for (#{oid})", oid)
        elsif type != :blob
          raise GitRPC::InvalidObject, "Invalid object type #{type}, expected blob"
        end

        object = parse_blob_object(oid, data, size, nil, nil)
      end
      object
    end

    # Internal: Maximum size we'll allow and truncate commit messages at.
    # If a message is longer than this value, we'll truncate it and return that.
    #
    # This value is kept here mostly so it can be stubbed by tests and
    # documented. It is not meant to be changed during normal usage of the
    # library.
    @commit_message_max_length = 65535
    (class << self; attr_accessor :commit_message_max_length; end)

    # Internal: Insert a key k into the result hash with value v, dealing with
    # duplicate and multiline headers suitable for commit and tag objects.
    def insert_textual_kv(result, key, val)
      if key == "parent"
        result[key] ||= []
        result[key] << val.chomp
      elsif key.start_with?("gpgsig")
        result[key] = val
      else
        result[key] = val.chomp
      end
    end

    # Internal: Parse a commit or tag, whose raw contents are in `content`, and
    # return a hash of headers and the message body.
    def parse_textual_object(content)
      headers, body = content.split(/\n(?:\n|\z)/, 2)
      body = nil unless content.include? "\n\n"
      key = nil
      val = nil
      result = {}
      headers.each_line do |ln|
        if ln.start_with?(" ")
          val << ln[1..]
        else
          insert_textual_kv(result, key, val) if key && val
          key, val = ln.split(/ /, 2)
        end
      end
      # Insert the newline that we chopped off in the split at the top.
      insert_textual_kv(result, key, val + "\n") if key && val
      [result, body]
    end

    # Computes the timezone offset as an integral number of seconds.
    #
    # This has a lot of custom logic to deal with the fact that many of our
    # monolith tests check for specific handling of invalid timestamps with
    # specific results.  See the backend tests for cases we need to gracefully
    # handle.
    def compute_tz_offset(tz_offset)
      if tz_offset && tz_offset =~ /\A([+-]+)(\d{,4})\z/
        mul = $1.each_char.inject(1) { |val, c| ((c == "-" ? -1 : 1) * val) }
        offset_i = mul * ($2[0...-2].to_i * 60 + $2[-2, 2].to_i) * 60
        offset_i.clamp(VALID_TZ_OFFSET_RANGE)
      else
        0
      end
    end

    def parse_author(author, encoding)
      return nil if author.nil?

      matches = author.match(/\A(?:(.*?)\s+)?<(.*)>(?: +(.*))?\z/)
      if matches.nil?
        raise GitRPC::InvalidObject, "Failed to parse author or committer"
      end
      author_name, author_email, timestamp = matches.captures
      author_name ||= "".dup
      timestamp ||= "0 +0000"
      epoch, offset = timestamp.match(/\A(\d+)(?: ([+-]+\d{,4}))?\z/)&.captures || ["0", "+0000"]
      epoch = epoch&.to_i
      if !epoch || epoch.abs > 0x7fffffffffffffff
        raise GitRPC::InvalidObject, "failed to parse signature - invalid Unix timestamp"
      end
      author_email = author_email.to_s.strip.gsub(/\.+\z/, "") unless author_email.empty?
      author_name = $1 if author_name =~ /\A\s*"(.*)"\s*\z/
      set_commit_encoding(author_name, encoding)
      set_commit_encoding(author_email, encoding)
      [author_name.scrub!, author_email.scrub!, [epoch, compute_tz_offset(offset)]]
    end

    def parse_commit_object(oid, content, skip_bad: false, read_trailers: false)
      headers, body = parse_textual_object(content)

      encoding = message_encoding_raw(body)
      set_commit_encoding(body, headers["encoding"] || encoding || "UTF-8")
      if body
        truncated_message = body[0, Backend.commit_message_max_length]
        was_truncated = truncated_message.size < body.size
      else
        truncated_message = nil
        was_truncated = false
      end

      commit_hash = {
        "oid"               => oid,
        "type"              => "commit",
        "tree"              => headers["tree"],
        "parents"           => headers["parent"] || [],
        "author"            => parse_author(headers["author"], headers["encoding"] || encoding || "UTF-8"),
        "committer"         => parse_author(headers["committer"], headers["encoding"] || encoding || "UTF-8"),
        "message"           => truncated_message,
        "message_truncated" => was_truncated,
        "message_shas"      => extract_and_expand_shas(truncated_message),
        "encoding"          => headers["encoding"] || encoding,
        "has_signature"     => headers.key?("gpgsig") || headers.key?("gpgsig-sha256")
      }

      commit_hash["trailers"] = parse_trailers(body, encoding) if read_trailers == :regexp
      commit_hash
    rescue GitRPC::InvalidObject
      if skip_bad
        nil
      else
        raise
      end
    end

    def extract_and_expand_shas(message)
      if message && message.valid_encoding?
        if !message.encoding.ascii_compatible?
          message = message.encode(::Encoding::UTF_8, :invalid => :replace, :undef => :replace)
        end
        # expand_shas is being converted from libgit2 to git. Since we don't
        # (yet) want that conversion to take effect here, where we directly use
        # the `expand_shas` backend, hardcode the libgit2/rugged implementation
        # instead.
        #expand_shas(message.scan(/\b[0-9a-f]{7,40}\b/), "commit")
        sha_list = message.scan(/\b[0-9a-f]{7,40}\b/)
        expected_type = "commit"
        rugged.expand_oids(sha_list, expected_type)
      else
        {}
      end
    end

    # Convert a Rugged author hash into an author tuple.
    #
    # author - Rugged author hash or nil.
    #
    # Returns a [name, email, time] tuple or nil when author is nil. The name
    # and email values are always strings. The time value is a [unixtime, offset]
    # array where both values are integers.
    def convert_author(author)
      return if author.nil?
      [author[:name].scrub!, author[:email].scrub!, [author[:time].to_i, author[:time].utc_offset]]
    end

    # Lookup a Rugged tree object and convert to GitRPC's simple object format.
    def get_tree_object(oid, header, skip_bad: false)
      res = spawn_git("ls-tree", ["-z", "--end-of-options", oid])
      unless res["ok"]
        err = res["err"].chomp
        msg = "#{err} (exit #{res["status"]})"
        if err.include?(NOT_GIT_REPO) # empty or malformed directory
          raise ::GitRPC::InvalidRepository, msg
        elsif err.include?("not a tree object")
          if skip_bad
            return nil
          else
            raise GitRPC::InvalidObject, "Invalid tree object #{oid}"
          end
        else
          raise ::GitRPC::Failure.new(::GitRPC::CommandFailed.new(res))
        end
      end
      entries = res["out"].split("\0").map do |ln|
        next if ln.empty?
        meta, name = ln.split("\t", 2)
        mode, type, eoid = meta.split(" ")
        [
          name,
          {
            "oid" => eoid,
            "type" => type,
            "mode" => mode.to_i(8),
            "name" => name.force_encoding("UTF-8"),
          },
        ]
      end.compact.to_h

      {
        "oid"       => oid,
        "type"      => "tree",
        "entries"   => entries,
      }
    end

    # Convert a Rugged tree entry into GitRPC's simple object format.
    def convert_tree_entries(tree)
      entries = {}
      tree.each do |entry|
        entries[entry[:name]] = {
          "oid"  => entry[:oid],
          "type" => entry[:type].to_s,
          "mode" => entry[:filemode],
          "name" => entry[:name]
        }
      end
      entries
    end

    # Internal: Maximum amount of bytes of blob data to attempt to read from
    # disk into memory. If this limit is exceeded, the object won't be read
    # from disk, and the object will be returned with no data.
    #
    # This value is kept here mostly so it can be stubbed by tests and
    # documented. It is not meant to be changed during normal usage of the
    # library.
    @blob_maximum_data_size = 5 * 1024 * 1024
    (class << self; attr_accessor :blob_maximum_data_size; end)

    # Internal: Maximum amount of bytes of blob data to return for one blob.
    # The default value is 500kb of blob data. This should allow blob data
    # to be cached.
    #
    # This value is kept here mostly so it can be stubbed by tests and
    # documented. It is not meant to be changed during normal usage of the
    # library.
    @blob_truncate_data_size = 500 * 1024
    (class << self; attr_accessor :blob_truncate_data_size; end)

    # Parse a blob response from Git and convert into GitRPC's simple object format.
    def parse_blob_object(oid, body, size, truncate = Backend.blob_truncate_data_size, limit = Backend.blob_maximum_data_size)
      blob_hash = {
        "type" => "blob",
        "size" => size,
        "data" => "",
        "truncated" => false,
        "size_over_limit" => false,
      }

      if (limit && size > limit) || !body
        blob_hash["oid"] = oid
        blob_hash["truncated"] = true
        blob_hash["size_over_limit"] = true
      else
        content = if truncate && size > truncate
          blob_hash["truncated"] = true
          body[0...truncate]
        else
          body
        end
        blob_hash["data"] = content
        blob_hash["oid"] = oid
        blob_hash["encoding"] = GitRPC::Encoding.guess_and_tag(content)
        blob_hash["binary"] = blob_hash["encoding"].nil?
      end

      blob_hash
    end

    # Lookup a Rugged blob and convert into GitRPC's simple object format.
    def get_blob_object(oid, header, truncate = Backend.blob_truncate_data_size, limit = Backend.blob_maximum_data_size)
      blob_hash = {
        "type" => "blob",
        "size" => header[:len],
        "data" => "",
        "truncated" => false,
        "size_over_limit" => false
      }

      if limit && header[:len] > limit
        blob_hash["oid"] = oid
        blob_hash["truncated"] = true
        blob_hash["size_over_limit"] = true
      else
        blob = rugged.lookup(oid)
        content = if truncate && blob.size > truncate
          blob_hash["truncated"] = true
          blob.content(truncate)[0...truncate]
        else
          blob.content[0...blob.size]
        end
        blob_hash["data"] = content
        blob_hash["oid"] = blob.oid
        blob_hash["encoding"] = GitRPC::Encoding.guess_and_tag(content)
        blob_hash["binary"] = blob_hash["encoding"].nil?
      end

      blob_hash
    end

    def parse_tag_object(oid, content, skip_bad: false)
      headers, body = parse_textual_object(content)
      message, signed = extract_tag_signature(body)
      message.force_encoding(headers["encoding"] || "UTF-8") if message

      unless headers["object"]
        raise GitRPC::InvalidObject, "Invalid tag object #{oid}"
      end

      {
        "oid"           => oid,
        "type"          => "tag",
        "name"          => headers["tag"],
        "message"       => message,
        "message_shas"  => extract_and_expand_shas(message),
        "has_signature" => signed,
        "tagger"        => headers["tagger"] ? parse_author(headers["tagger"], headers["encoding"] || "UTF-8") : nil,
        "target"        => headers["object"],
        "target_type"   => headers["type"],
      }
    rescue GitRPC::InvalidObject
      if skip_bad
        nil
      else
        raise
      end
    end

    # Split the PGP signature part out of an annotated tag's message.
    #
    # message - String message or nil when no message has been set.
    #
    # Returns a [message, has_signature] array.
    def extract_tag_signature(message)
      if message.nil?
        [nil, false]
      elsif !message.valid_encoding?
        [message, false]
      elsif message.match(/^#{GPG_SIGNATURE_PREFIX}$/)
        message = message.split("#{GPG_SIGNATURE_PREFIX}\n", 2).first
        [message, true]
      elsif message.match(/^#{SSH_SIGNATURE_PREFIX}$/)
        message = message.split("#{SSH_SIGNATURE_PREFIX}\n", 2).first
        [message, true]
      elsif message.match(/^#{SMIME_SIGNATURE_PREFIX}$/)
        message = message.split("#{SMIME_SIGNATURE_PREFIX}\n", 2).first
        [message, true]
      else
        [message, false]
      end
    end

    # Internal: Returns the encoding name for a commit message and
    # tags the message with a Ruby-compatible encoding based on that.
    def message_encoding(commit)
      message_encoding_raw(commit.message)
    end

    # Internal: Returns the encoding name for a commit message and
    # tags the message with a Ruby-compatible encoding based on that.
    # `message` is the raw message itself.
    def message_encoding_raw(message)
      if GitRPC::Encoding.detectable?(message)
        encoding = GitRPC::Encoding.guess_and_tag(message)
      end

      encoding || GitRPC::Encoding::UTF8
    end

    def set_commit_encoding(text, encoding)
      return nil unless text
      begin
        enc = ::Encoding.find(encoding)
        text.force_encoding(enc)
      rescue ArgumentError
        text.force_encoding("ASCII-8BIT")
      end
    end

    # Internal: Set the detected encoding for the filename and return
    # what it was detected to be.
    def set_filename_encoding(filename)
      if GitRPC::Encoding.detectable?(filename)
        GitRPC::Encoding.guess_and_tag(filename)
      end
    end

    def object_reader(mode, objects = [], limit = Backend.blob_maximum_data_size, &block)
      rdr = ObjectReader.new(native, limit: limit)
      objects.map do |obj|
        block.yield rdr.object(obj, mode).fetch_values(:oid, :type, :size, :data) { nil }
      end
    ensure
      rdr&.close
    end
  end
end
