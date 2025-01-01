# typed: false
# frozen_string_literal: true

# Defines methods that help transition from GitRPC to Spokes.
module GitRepository::SpokesAdapter
  include Scientist

  #### Pre-Spokes transition methods ####

  # Outside of tests, this function is essentially a no-op, always returning
  # 'false' and  allowing the libgit2 -> git tests to run as usual.
  #
  # In some tests, we check the number of calls made to GitRPC. In these cases,
  # the double-calls of the experiments will trigger failure. This function
  # should be mocked to return 'true' for those tests.
  def disable_libgit2_to_git_experiments; false; end

  # Outside of tests, this function is essentially a no-op, always returning
  # 'false' and allowing the Spokes API operations to run as usual.
  #
  # In some tests, we synthesize fake data that exists in the database but
  # doesn't actually exist when accessed through spokesd, which can trigger
  # failures. This function should be mocked to return 'true' for those tests.
  def disable_spokes_api_conversions; false; end

  # Public: Read the reference pointed to by the symbolic HEAD reference.
  #
  # Returns a string containing the fully-qualified reference that HEAD points
  # to, or raises GitRPC::CommandFailed.
  def get_default_branch
    if self.id
      cache_key = repository_reference_cache_key("get_default_branch")
      cache_fetch(cache_key, backend_method: :get_default_branch) do
        self.spokes_api.get_default_branch
      end
    else
      cache_key = repository_reference_cache_key("read_symbolic_ref", "HEAD")
      cache_fetch(cache_key, backend_method: :read_symbolic_ref) do
        self.rpc.read_symbolic_ref("HEAD")
      end
    end
  end

  # This method is used by '/internal/raw/gist' to resolve the gist blob.
  def gist_blob_oid_by_path(path, commit_oid)
    read_tree_entry_oid(commit_oid, path, "blob", :QUALITY_OF_SERVICE_FAIL_FAST)
  end

  # Public: The main git object reading interface. Reads commit, tree,
  # blob, and tag objects from cache and then the object store and presents as
  # simple hash data structures.
  #
  # This method is an adapter for the read_objects method in the GitRPC, returning the same
  # data structure as the existing GitRPC method, so the existing clients
  def read_objects(oids = [], type = nil, skip_bad = false, feature_flag: nil)
    if feature_enabled?(feature_flag)
      run_read_objects_spokes_api(oids, type, skip_bad, feature_flag: feature_flag)
    else
      science "read_objects_spokes_api_experiment" do |e|
        e.context({
          oids: oids,
          repository: self,
        })
        e.use { self.rpc.read_objects(oids, type, skip_bad) }
        e.try { run_read_objects_spokes_api(oids, type, skip_bad) }
        e.compare do |control, candidate|
          next false if control.size != candidate.size
          identical = true
          control.zip(candidate).each do |control_object, candidate_object|
            # while reading "blobs" we have find a few scenarios (mainly reading CODEOWNERS files) where the only
            # difference is that the control has an additional \n at the end of the data attribute,
            # but all the other attributes are identical.
            # We have identified a couple of public repositories where this happens, and we have not been able to
            # reproduce it in a controlled environment.
            # For now, let's consider them identical and log some additional info that could help us to diagnose
            # the issue
            if control_object["type"] == candidate_object["type"] && control_object["type"] == "blob"
              if control_object["data"] == "#{candidate_object["data"]}\n"
                # Log some additional info that could help us to diagnose the issue
                GitHub.logger.info(
                  "ReadObjects trailing newline mismatch",
                  "code.namespace" => self.class.name,
                  "code.function" => "read_objects",
                  "repo" => self,
                  "control_data" => control_object["data"],
                  "control_data_size" => control_object["data"].size,
                  "control_attribute_size" => control_object["size"],
                  "candidate_data" => candidate_object["data"],
                  "candidate_data_size" => candidate_object["data"].size,
                  "candidate_attribute_size" => candidate_object["size"],
                )

                control_object["data"] = candidate_object["data"]
                control_object["size"] = candidate_object["size"]
              end
            end

            # The new API doesn't return truncated objects, but a ERROR_REASON_TOO_LARGE error. In this scenario
            # we only have the very basic information of the requested object: oid, size and type.

            # When GitRPC `read_objects` returns a truncated object it doesn't mean that the object returned
            # by the SpokesAPI is truncated too, because the allowed max size of the latter is bigger.

            # For now, and trying to keep this as simple as possible, when we get a truncated object,
            # let's consider them identical if they have the same oid and type.
            if control_object["truncated"] || control_object["message_truncated"]
              if (control_object["oid"] != candidate_object["oid"]) ||
                  (control_object["type"] != candidate_object["type"])
                identical = false
                break
              end
            else
              if control_object != candidate_object
                identical = false
                break
              end
            end
          end
          identical
        end
        e.compare_errors do |control, candidate|
          if (control.is_a? GitRPC::ObjectMissing) && (candidate.is_a? GitRPC::ObjectMissing) ||
             (control.is_a? GitRPC::InvalidObject) && (candidate.is_a? GitRPC::InvalidObject) ||
             (control.is_a? GitRPC::BadObjectState) && (candidate.is_a? GitRPC::InvalidObject)
            true
          else
            control.class == candidate.class && control.message == candidate.message
          end
        end
        e.run_if { !self.disable_spokes_api_conversions }
      end
    end
  end

  def run_read_objects_spokes_api(oids = [], type = nil, skip_bad = false, feature_flag: nil)
    return [] if oids.empty?

    # load as many objects as we can from cache
    keys = oids.map do |oid|
      GitRPC::Util.ensure_valid_full_oid(oid)
      object_key(oid)
    end

    objects = cache_get_multi(keys, backend_method: :read_objects) || {}

    # validate loaded objects are of the expected type
    validate_objects(objects, type, skip_bad) if type

    # build list of cache miss oids
    miss_oids = []
    keys.zip(oids).each do |key, oid|
      if objects[key].nil?
        miss_oids << oid
      end
    end



    # load missing objects from the backend and write to cache
    if miss_oids.any?
      # The ReadObjects API has a limit of 1000 oids per request, so let's batch the requests
      miss_oids.each_slice(1000) do |batch|
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        response = self.spokes_api.read_objects(oids: batch, types: type != nil ? Array.new(batch.size, type.to_s) : nil)

        # Let's look for the commits in all the additional repositories indicated by the caller
        # through the extend_rpc_alternates method. Search only the ones we haven't found in the self
        # repo which has performed this call
        if !@alternate_repositories.nil? && @alternate_repositories.size > 0
          missing_oids = response.objects.filter_map { |obj| obj.object.oid.id if obj.error_object != nil && obj.error_object.error_reason == :ERROR_REASON_MISSING }
          oids = search_missing_oids_in_repos(missing_oids, @alternate_repositories, type)
          response.objects.map! { |obj| oids[obj.object.oid.id] != nil ? oids[obj.object.oid.id] : obj }
        end

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        GitHub.logger.info(
          "run_read_objects_spokes_api",
          "code.namespace" => self.class.name,
          "code.function" => "read_objects",
          "code.args" => batch,
          "repo" => self,
          "feature_flag" => feature_flag,
          "duration" => (end_time - start_time) * 1_000,
        )

        objs = map_response(response, skip_bad)

        objs.compact.each do |object|
          key = object_key(object["oid"])
          objects[key] = object
          GitHub.cache.set(key, object)
        end
      end
    end

    # maintain original order of objects
    keys.map do |key|
      object = objects[key]
      next unless object

      object
    end.compact
  rescue GitRPC::ObjectMissing => boom
    GitHub.cache.delete(object_key(boom.oid))
    raise
  end

  def search_missing_oids_in_repos(oids, repos, type)
    result = {}
    repos.each do |repo|
      if oids.size > 0
        types = type.nil? ? Array.new(oids.size, type.to_s) : nil
        r = repo.spokes_api.read_objects(oids: oids, types: types)
        oids = oids.select do |oid|
          found = search_missing_oid_in_objects(oid, r.objects) if result[oid].nil?
          result[oid] = found if found != nil
          found.nil?
        end
      end
    end
    result
  end

  def search_missing_oid_in_objects(oid, objects)
    objects.find do |o|
      oid == o.object.oid.id && o.error_object.nil?
    end
  end

  # Use this class to model the error when we asked for an object that's too big
  class ObjectTooBigError < StandardError; end

  # Private: Maps the response from Spokes API to the format expected by
  # the existing callers of the GitRPC read_objects method.
  def map_response(response, skip_bad)
    response.objects.map do |obj|
      if obj.commit_object != nil
        map_commit(obj)
      elsif obj.tree_object != nil
        map_tree(obj)
      elsif obj.blob_object != nil
        map_blob(obj)
      elsif obj.tag_object != nil
        map_tag(obj)
      elsif obj.error_object != nil
        if skip_bad
          map_error(obj)
        else
          case obj.error_object.error_reason
          when :ERROR_REASON_MISSING
            raise GitRPC::ObjectMissing.new(obj.error_object.error, obj.object.oid)
          when :ERROR_REASON_AMBIGUOUS
            raise GitRPC::InvalidObject.new(obj.error_object.error)
          when :ERROR_REASON_TYPE_MISMATCH
            raise GitRPC::InvalidObject.new(obj.error_object.error)
          when :ERROR_REASON_INVALID
            raise GitRPC::InvalidObject.new(obj.error_object.error)
          when :ERROR_REASON_TOO_LARGE
            # The caller asked to raise an exception (skip_bad = false) when an error occurs.
            # However, we are in a special case (object too big) and we still want to return the basic object info
            # Note this is the behavior of the existing read_objects method and we are keeping it to avoid breaking
            # callers.
            # A client using the Spokes API to read objects doesn't necessarly needs to mimic this behavior.
            map_error(obj)
          else
            raise GitRPC::Error.new(obj.error_object.error)
          end
        end
      else
        raise ArgumentError, "invalid object type #{obj.class}"
      end
    end
  end

  def map_error(obj)
    return nil if obj.error_object.error_reason != :ERROR_REASON_TOO_LARGE
    # if the error indicates that the message was too big to read, we
    # still can return the basic information of the object without the
    # message.
    type = map_type(obj.object.type)
    basic_info = {
      "oid"               => obj.object.oid.id,
      "type"              => type,
      "size"              => obj.object.size,
    }

    basic_info["truncated"] = true if type == "blob"
    basic_info["message_truncated"] = true if type == "commit"

    basic_info
  end

  def map_trailers(trailers)
    trailers.group_by { |trailer| trailer.key.downcase }.transform_keys(&:downcase).transform_values do |trailers|
      trailers.map { |trailer| trailer.value }
    end
  end

  def map_expanded_oids(message_oids)
    message_oids.filter_map do |expanded_oid|
      [expanded_oid.short_oid.name, expanded_oid.long_oid.id] if expanded_oid.error.nil?
    end.to_h
  end

  def map_commit(obj)
    commit_object = {
      "oid"               => obj.object.oid.id,
      "type"              => "commit",
      "tree"              => obj.commit_object.tree_oid.id,
      "parents"           => obj.commit_object.parents.map(&:id),
      "trailers"          => map_trailers(obj.commit_object.trailers),
      "message_truncated" => false,
      "message_shas"      => map_expanded_oids(obj.commit_object.message_oids),
      "has_signature"     => obj.commit_object.signature != "",
    }

    data_encoded = obj.commit_object.message.dup
    encoding = obj.commit_object.encoding
    if encoding == ""
      encoding = GitRPC::Encoding.detectable?(data_encoded) ? GitRPC::Encoding.guess(data_encoded)[:encoding] : GitRPC::Encoding::UTF8
    end
    commit_object["encoding"] = encoding
    GitRPC::Encoding.tag_compatible(data_encoded, encoding)
    commit_object["message"] = data_encoded

    commit_object["author"] = map_attribution(obj.commit_object.author, encoding)
    commit_object["committer"] = map_attribution(obj.commit_object.committer, encoding)

    commit_object
  end

  def map_attribution(attribution, encoding)
    name = attribution.name.dup
    email = attribution.email.dup
    if !encoding.nil?
      GitRPC::Encoding.tag_compatible(name, encoding)
      GitRPC::Encoding.tag_compatible(email, encoding)
    end

    [name, email, [attribution.date.timestamp.seconds, attribution.date.offset]]
  end

  def map_tree(obj)
    {
      "oid"      => obj.object.oid.id,
      "type"     => "tree",
      "entries"  => obj.tree_object.entries.each_with_object({}) do |tree_entry, hash|
                      hash[tree_entry.path.name] = {
                        "oid" => tree_entry.object.oid.id,
                        "mode" => tree_entry.mode.mode,
                        "name" => tree_entry.path.name,
                        "type" => map_type(tree_entry.object.type),
                      }
                    end
    }
  end

  def map_blob(obj)
    blob_hash = {
      "oid" => obj.object.oid.id,
      "type" => "blob",
      "size" => obj.object.size,
      "truncated" => false,
      "size_over_limit" => false,
    }

    data_encoded = obj.blob_object.data.dup
    if obj.blob_object.encoding != ""
      blob_hash["encoding"] = obj.blob_object.encoding
      GitRPC::Encoding.tag_compatible(data_encoded, obj.blob_object.encoding)
    else
      blob_hash["encoding"] = GitRPC::Encoding.guess_and_tag(data_encoded)
    end

    blob_hash["data"] = data_encoded

    blob_hash["binary"] = blob_hash["encoding"].nil? ? true : false

    blob_hash
  end

  def map_tag(obj)
    {
      "oid"           => obj.object.oid.id,
      "type"          => "tag",
      "name"          => obj.tag_object.name,
      "message"       => obj.tag_object.message,
      "message_shas"  => map_expanded_oids(obj.tag_object.message_oids),
      "has_signature" => obj.tag_object.signature != "",
      "tagger"        => map_attribution(obj.tag_object.tagger, nil),
      "target"        => obj.tag_object.target.oid.id,
      "target_type"   => map_type(obj.tag_object.target.type)
    }
  end

  def map_type(type)
    case type
    when :TYPE_BLOB
      "blob"
    when :TYPE_TREE
      "tree"
    when :TYPE_COMMIT
      "commit"
    when :TYPE_TAG
      "tag"
    else
      nil
    end
  end

  def object_key(oid)
    parts = [
      oid,
      GitRPC::Backend.blob_maximum_data_size,
      GitRPC::Backend.blob_truncate_data_size,
      "v6",
    ]
    content_cache_key(*parts)
  end

  # Internal: helper method to validate that all objects in a collection
  # are of a specific type.
  #
  # objects - An array of object hashes
  # type    - The git object type name to validate against as a string. Must
  #           be 'commit', 'tree', 'blob', or 'tag'.
  #
  # Returns nothing. Raises a GitRPC::InvalidObject exception if an object
  # passes validation.
  def validate_objects(objects, type, skip_bad)
    type = type.to_s
    objects.reject! do |_, object|
      if object.nil?
        true
      elsif type && type == object["type"]
        false
      else
        if skip_bad
          true
        else
          raise GitRPC::InvalidObject, "Invalid object type #{object['type']}, expected #{type}"
        end
      end
    end
  end

  # Public: Fetch a single entry in a tree by the path.
  #
  # Returns the 40c OID of the tree entry. If no path is passed, the oid of the
  # root tree is returned. If the path does not exist, raises GitRPC::NoSuchPath.
  # If a type is passed and the object at the path does not match the type,
  # a `GitRPC::InvalidObject` error is raised.
  def read_tree_entry_oid(oid, path = nil, type = nil, qos = nil)
    GitRPC::Util.ensure_valid_full_oid(oid)

    path = GitRPC::Util.normalize_path(path)
    key = "#{path}:#{type}"

    key = content_cache_key("read_tree_entry_oid:v6", oid, sha256(key))
    cache_fetch(key, backend_method: :read_tree_entry_oid) do
      self.spokes_api.read_tree_entry_oid(oid: oid, path: path, type: type, qos: qos)
    end
  end

  def read_object_headers(oids)
    if feature_enabled?(:read_object_headers_spokes)
      run_read_object_headers_spokes_api(oids)
    else
      science "read_object_headers_spokes_api_experiment" do |e|
        e.context({
          oids: oids,
          repository: self,
        })
        e.use { self.rpc.read_object_headers(oids) }
        e.try { run_read_object_headers_spokes_api(oids) }
        e.compare_errors do |control, candidate|
          if (control.is_a? GitRPC::ObjectMissing) && (candidate.is_a? GitRPC::ObjectMissing)
            true
          else
            control.class == candidate.class && control.message == candidate.message
          end
        end
      end
    end
  end

  def run_read_object_headers_spokes_api(oids)
    return [] if oids.empty?
    # ensure each OID is valid
    keys = oids.map do |oid|
      GitRPC::Util.ensure_valid_full_oid(oid)
      content_cache_key(oid)
    end

    # load headers from cache
    object_headers = cache_get_multi(keys, backend_method: :read_object_headers) || {}

    # track the oids that were missing from the cache
    miss_oids = []
    headers_to_return = []
    keys.zip(oids).each do |key, oid|
      miss_oids << oid if object_headers[key].nil?
    end

    # fetch the missing ones and update the cache
    if miss_oids.any?
      # get missing headers from spokes
      miss_oids.each_slice(SpokesAPI::Client::RESOLVE_OBJECT_BATCH_SIZE).flat_map do |batch|
        headers = self.spokes_api.resolve_objects(oids: batch)
        # cache the headers with content_cache_key(oid) -> {:type,:size}
        miss_oids.zip(headers.items).each do |oid, object_header|
          oid_key = content_cache_key(oid)
          if object_header.error != ""
            raise GitRPC::ObjectMissing.new(oid, object_header.error)
          end
          # convert :TYPE_BLOB to "blob" etc...
          type_as_readable_string = map_type(object_header.object&.type)
          object_header_value = { "type" => type_as_readable_string, "size" => object_header.object&.size }
          headers_to_return << object_header_value
          GitHub.cache.set(oid_key, object_header_value)
        end
      end
    end

    if object_headers.any?
      headers_to_return << object_headers.values_at(*keys)
    end

    headers_to_return.flatten

  rescue GitRPC::ObjectMissing => boom
    GitHub.cache.delete(object_key(boom.oid))
    raise
  end

  # Public: Create a merge commit
  #
  # base           - the commit to merge into
  # head           - the commit to merge
  # author         - author information hash
  # commit_message - the message to use for the commit
  def create_merge_commit(base, head, author, commit_message, options = {}, &block)
    options = options.merge(use_tmp_objdir_mode: "migrate-on-success")

    if repository.feature_enabled?(:tmp_objdir_experiment)
      options = options.merge(dogstats: true)
      options[:use_tmp_objdir_mode] = "pack-and-migrate-on-success" if repository.feature_enabled?(:tmp_objdir_experiment_pack)
    end

    result = self.rpc.create_merge_commit(base, head, author, commit_message, options, &block)
    result[4].each { |args| GitHub.dogstats.count(*args) } unless result[4].nil?
    result
  end

  # Internal (tests only): All of the possible refs_keys
  def refs_keys
    GitRPC::Util::READ_REFS_FILTERS.map { |filter| refs_key(filter) }
  end

  #############################################################################

  #### In-transition methods ####

  def blame_tree(commit_oid, root = nil, recursive = true)
    GitRPC::Util.ensure_valid_full_oid(commit_oid)

    key = content_cache_key("blame-tree", commit_oid, sha256(root), recursive, "v4")
    cache_fetch(key, backend_method: :blame_tree) do
      begin
        self.spokes_api.blame_tree(commit_oid, root, recursive)
      rescue SpokesAPI::TimedOut
        raise GitRPC::Timeout.new
      end
    end
  end

  def diff_summary_cached?(commit1_oid, commit2_oid, base_commit_oid, algorithm: GitRPC::Client::DIFF_SUMMARY_DEFAULT_ALGORITHM)
    ignore_whitespace = algorithm == GitRPC::Diff::ALGORITHM_IGNORE_WHITESPACE
    key = content_cache_key("read-diff-summary", "v1", commit1_oid, commit2_oid, base_commit_oid, ignore_whitespace)
    self.rpc.diff_summary_cached?(commit1_oid, commit2_oid, base_commit_oid, algorithm: algorithm) ||
      GitHub.cache.exist?(key)
  end

  def read_diff_summary(commit1_oid, commit2_oid, base_commit_oid, commit1_repo: nil, commit2_repo: nil, timeout: GitRPC::Client::DIFF_SUMMARY_TIMEOUT, algorithm: GitRPC::Client::DIFF_SUMMARY_DEFAULT_ALGORITHM)
    ignore_whitespace = algorithm == GitRPC::Diff::ALGORITHM_IGNORE_WHITESPACE
    if GitHub.spokesd_enabled? && self.feature_enabled?(:read_diff_summary_spokes_api)
      self.read_diff_summary_spokes_api(commit1_oid, commit2_oid, base_commit_oid, commit1_repo:, commit2_repo:, timeout:, ignore_whitespace:)
    else
      science "read_diff_summary_spokes_api_experiment" do |e|
        e.context({
          commit1_oid: commit1_oid,
          commit2_oid: commit2_oid,
          commit1_repo: commit1_repo&.id,
          commit2_repo: commit2_repo&.id,
          base_commit_oid: base_commit_oid,
          timeout: timeout,
          algorithm: algorithm,
          repository: self.id,
          alternates: self.rpc.options[:alternates],
        })
        e.use { self.rpc.read_diff_summary(commit1_oid, commit2_oid, base_commit_oid, timeout:, algorithm:) }
        e.try { self.read_diff_summary_spokes_api(commit1_oid, commit2_oid, base_commit_oid, commit1_repo:, commit2_repo:, timeout:, ignore_whitespace:) }
        e.run_if { !self.disable_spokes_api_conversions && GitHub.spokesd_enabled? }
        e.ignore do |control, candidate|
          # Our control may not return a too-busy error, but if our candidate
          # does, that's expected (and even desired in some cases).
          #
          # If one side got a timeout and the other didn't, also don't consider
          # that a mismatch.
          next true if candidate&.unavailable_error&.is_a?(SpokesAPI::ResourceExhausted) ||
            control&.unavailable_reason == "timeout" ||
            candidate&.unavailable_reason == "timeout" ||
            control&.unavailable_reason == "too busy" ||
            candidate&.unavailable_reason == "too busy"

          GitHub.logger.info(
            "ReadDiffSummary backtrace",
            "code.namespace" => self.class.name,
            "code.function" => "read_diff_summary",
            "backtrace" => Thread.current.backtrace.join("\n").inspect,
          )
          false
        end
      end
    end
  end

  def read_diff_summary_spokes_api(commit1_oid, commit2_oid, base_commit_oid, commit1_repo: nil, commit2_repo: nil, timeout: GitRPC::Client::DIFF_SUMMARY_TIMEOUT, ignore_whitespace: false)
    GitRPC::Util.ensure_valid_full_oid(commit2_oid)
    GitRPC::Util.ensure_valid_full_oid(commit1_oid) if commit1_oid
    GitRPC::Util.ensure_valid_full_oid(base_commit_oid) if base_commit_oid

    timeout_key = content_cache_key("read-diff-summary", "v1", commit1_oid, commit2_oid, base_commit_oid, ignore_whitespace, "timed-out")
    previous_timeout = GitHub.cache.fetch(timeout_key) { nil }

    if previous_timeout && timeout <= previous_timeout
      return GitRPC::Diff::Summary.unavailable(reason: "timeout", error: nil)
    end

    key = content_cache_key("read-diff-summary", "v1", commit1_oid, commit2_oid, base_commit_oid, ignore_whitespace)
    client = self.spokes_api(timeout: timeout)
    begin
      data = cache_fetch(key, backend_method: :read_diff_summary) do
        client.read_diff_summary(commit1_oid:, commit2_oid:, base_commit_oid:, commit1_repo:, commit2_repo:, with_stats: true, ignore_whitespace:)
      end
      null_oid = nil
      deltas = data[:deltas].take(GitRPC::Diff::DiffTreeParser::MAX_FILES).flat_map do |d|
        # GitRPC always emits these as binary strings.
        d[:old_file][:path] = d[:old_file][:path].b
        d[:new_file][:path] = d[:new_file][:path].b

        if d[:status] == "T"
          null_oid ||= d[:old_file][:oid].gsub(/[0-9a-f]/, "0")
          # gitrpcd doesn't split these changes, but GitRPC does.  Split them
          # here to prevent mismatches.
          [
            GitRPC::Diff::Summary::Delta.new(
              old_file: d[:old_file],
              new_file: {
                oid: null_oid, mode: GitRPC::NULL_MODE,
                path: d[:old_file][:path],
              },
              additions: d[:deletions].nil? ? nil : 0,
              deletions: d[:deletions],
              status: "D", similarity: 0,
            ),
            GitRPC::Diff::Summary::Delta.new(
              old_file: {
                oid: null_oid, mode: GitRPC::NULL_MODE,
                path: d[:new_file][:path],
              },
              additions: d[:additions],
              deletions: d[:additions].nil? ? nil : 0,
              new_file: d[:new_file],
              status: "A", similarity: 0,
            ),
          ]
        else
          [GitRPC::Diff::Summary::Delta.new(**d)]
        end
      end
      GitRPC::Diff::Summary.new(deltas: deltas, **data.slice(:additions, :deletions, :changed_files))
    rescue SpokesAPI::TimedOut, Timeout::ExitException => boom
      GitHub.cache.set(timeout_key, timeout)
      GitRPC::Diff::Summary.unavailable(reason: "timeout", error: boom)
    rescue SpokesAPI::NotFound => boom
      if boom.to_s.start_with? "object not found"
        GitRPC::Diff::Summary.unavailable(reason: "missing commits", error: boom)
      else
        # Missing repository.
        GitRPC::Diff::Summary.unavailable(reason: "corrupt", error: boom)
      end
    rescue SpokesAPI::ResourceExhausted => boom
      GitRPC::Diff::Summary.unavailable(reason: "too busy", error: boom)
    rescue SpokesAPI::Error => boom
      GitRPC::Diff::Summary.unavailable(reason: "corrupt", error: boom)
    end
  end

  def read_latest_wiki_pages(oid)
    if !GitRPC::Util.valid_full_oid?(oid)
      raise ::GitRPC::InvalidFullOid, "wrong argument type #{oid.inspect} (expected 40c String OID)"
    end

    wiki_key = content_cache_key("latest-wiki-pages", oid, "v3")
    GitHub.cache.fetch(wiki_key) do
      entries = blame_tree(oid)

      commit_oids = []
      entries.select! do |path, commit_oid|
        filename = ::File.basename(path)
        if GitRPC::Backend.valid_wiki_page?(filename)
          commit_oids << commit_oid
        end
      end

      commits = {}
      self.rpc.read_commits(commit_oids.uniq).each do |commit|
        commits[commit["oid"]] = commit
      end

      pages = []
      entries.each do |path, commit_oid|
        commit = commits[commit_oid]
        pages << [path, commit]
      end

      pages.sort do |entry_a, entry_b|
        time1 = Time.at(*entry_a[1]["author"][2])
        time2 = Time.at(*entry_b[1]["author"][2])

        time2 <=> time1
      end

      pages.map do |entry, commit|
        [entry, commit["oid"]]
      end
    end
  end

  def resolve_references(refnames)
    refname_to_cache_key = refnames.map do |refname|
      [refname, repository_reference_cache_key("resolve_references", "v1", Digest::SHA256.hexdigest(refname))]
    end.to_h

    cached_refs = {}
    missing_refnames = []

    target_oids_from_cache = cache_get_multi(refname_to_cache_key.values, backend_method: :resolve_references)
    refnames.each do |refname|
      cache_key = refname_to_cache_key[refname]
      if target_oids_from_cache.has_key?(cache_key)
        cached_refs[refname] = target_oids_from_cache[cache_key]
      else
        missing_refnames << refname
      end
    end

    if missing_refnames.any?
      results = if self.id
        missing_refnames.each_slice(SpokesAPI::Client::resolve_references_ref_limit).flat_map do |batch|
          self.spokes_api.resolve_references(batch)
        end
      else
        self.rpc.read_qualified_refs(missing_refnames, do_cache: false)
      end

      missing_refnames.zip(results) do |refname, result|
        target_oid = result[1]
        cached_refs[refname] = target_oid
        GitHub.cache.set(refname_to_cache_key[refname], target_oid)
      end
    end

    refnames.zip(cached_refs.values_at(*refnames))
  end

  private

  # Internal: run and instrument GitHub.cache.get_multi
  def cache_get_multi(keys, backend_method:)
    GitHub.instrument("cache_get_multi.spokes_adapter", backend_method: backend_method, keys: keys) do |instrument_payload|
      results = GitHub.cache.get_multi(keys)
      instrument_payload[:results] = results
      results
    end
  end

  # Internal: run and instrument GitHub.cache.fetch.
  def cache_fetch(key, *args, backend_method:)
    cache_result = "hit"
    GitHub.cache.fetch(key, *args) do
      cache_result = "miss"
      yield
    end
  ensure
    GitHub.instrument("cache_get.spokes_adapter", backend_method:, cache_result: cache_result)
  end

  # Internal: Generate a cache key for an immutable and content addressable
  # piece of content like a commit, tree, or blob. This uses the content_key
  # attribute as a base prefix. See the attribute docs for more info on
  # content addressable cache keys.
  #
  # parts - Array of additional stuff to include in the key. This must consist
  #         of valid memcache key characters only. Use the sha256 digest for path
  #         names and other elements that may include weird characters.
  #
  # Returns a string key suitable for use with memcache.
  def content_cache_key(*parts)
    [cache_version, spokes_cache_key, *parts].join(":")
  end

  # Internal: Generate a cache key for the repository's references. This key
  # changes whenever the repository's ref state changes.
  #
  # This intentionally differs from the equivalent GitRPC function by adding the
  # "spokes_adapter" element to the key. Doing so prevents cache poisoning in
  # situation where a method moved to SpokesAdapter returns bad results and
  # needs to be rolled back.
  #
  # parts - Array of additional cache key elements.
  #
  # Returns a string key suitable for use with memcache.
  def repository_reference_cache_key(*parts)
    [cache_version, "spokes_adapter", self.rpc.repository_key, self.rpc.repository_reference_key, *parts].join(":")
  end

  def cache_version
    "v2"
  end

  # Internal: Cache key used to store the main refs hash.
  def refs_key(filter)
    repository_reference_cache_key("refs", "v4", filter)
  end

  def spokes_cache_key
    if self.responds_to?(:spokes_cache_key)
      "spokes_adapter:#{self.spokes_cache_key}"
    else
      # If SpokesAdapter is included in more classes, the appropriate cases
      # must be added above to avoid this error
      raise "Unknown GitRPC cache key for #{self.class.name}"
    end
  end

  # Internal: Generate an sha256 sum of the passed strings. Used to
  # generate fixed length representation of variable length parameters
  # to be used as cache keys
  #
  # parts - Array of variable length keys to sha256sum
  #
  # Returns a sha256 hash string of the parameters
  def sha256(*parts)
    Digest::SHA256.hexdigest(parts.join(":"))
  end

end
