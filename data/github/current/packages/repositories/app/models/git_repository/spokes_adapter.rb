# typed: false
# frozen_string_literal: true

# Defines methods that help transition from GitRPC to Spokes.
module GitRepository::SpokesAdapter
  include Scientist

  DIFF_SUMMARY_TIMEOUT = 8
  DIFF_SUMMARY_DEFAULT_ALGORITHM = "vanilla".freeze

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

  # Public: The main git object reading interface. Reads commit, tree,
  # blob, and tag objects from cache and then the object store and presents as
  # simple hash data structures.
  #
  # This method is an adapter for the read_objects method in the GitRPC, returning the same
  # data structure as the existing GitRPC method, so the existing clients
  def read_objects(
    oids = [], type = nil, skip_bad = false, custom_rpc: nil, alternate_repos: [], qos: nil,
    disable_write_cache: false)

    if self.id
      run_read_objects_spokes_api(oids, type, skip_bad, alternate_repos: alternate_repos, qos: qos, disable_write_cache: disable_write_cache)
    else
      custom_rpc.nil? ? self.rpc.read_objects(oids, type, skip_bad) : custom_rpc.read_objects(oids, type, skip_bad)
    end
  end

  def run_read_objects_spokes_api(oids = [], type = nil, skip_bad = false, alternate_repos: [], qos: nil, disable_write_cache: false)
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
        response = self.spokes_api.read_objects(oids: batch, types: type != nil ? Array.new(batch.size, type.to_s) : nil, qos: qos)

        # Let's look for the commits in all the additional repositories indicated by the caller
        # through the extend_rpc_alternates method. Search only the ones we haven't found in the self
        # repo which has performed this call

        alt_repos = compute_alternate_repos(alternate_repos)

        if alt_repos.size > 0
          missing_oids = response.objects.filter_map { |obj| obj.object.oid.id if obj.error_object != nil && obj.error_object.error_reason == :ERROR_REASON_MISSING }
          oids = search_missing_oids_in_repos(missing_oids, alt_repos, type, qos)
          response.objects.map! { |obj| oids[obj.object.oid.id] != nil ? oids[obj.object.oid.id] : obj }
        end

        objs = map_response(response, skip_bad)

        objs.compact.each do |object|
          key = object_key(object["oid"])
          objects[key] = object
          GitHub.cache.set(key, object) if !disable_write_cache
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

  def compute_alternate_repos(repos)
    return @alternate_repositories if !@alternate_repositories.nil? && @alternate_repositories.size > 0
    return repos if !repos.nil? && repos.size > 0
    []
  end

  def search_missing_oids_in_repos(oids, repos, type, qos)
    result = {}
    types = type != nil ? Array.new(oids.size, type.to_s) : nil

    repos.each do |repo|
      if oids.size > 0
        r = repo.spokes_api.read_objects(oids: oids, types: types, qos: qos)
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
          if obj.object&.type != :TYPE_BLOB
            nil
          else
            # We still want to return basic object info if the large object is a blob to mimic GitRPC behavior
            map_error(obj)
          end
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
            # However, we are in a special case (object too big) and we still want to return the basic object info for
            # blob objects.
            # Note this is the behavior of the existing read_objects method and we are keeping it to avoid breaking
            # callers.
            # A client using the Spokes API to read objects doesn't necessarly needs to mimic this behavior.
            if obj.object&.type != :TYPE_BLOB
              raise GitRPC::InvalidObject.new(obj.error_object.error)
            else
              map_error(obj)
            end
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
    type = SpokesAPI::Util.object_type_to_str(obj.object.type)
    basic_info = {
      "oid"               => obj.object.oid.id,
      "type"              => type,
      "size"              => obj.object.size,
    }

    if type == "blob"
      basic_info["truncated"] = true
      basic_info["size_over_limit"] = true
      # The actual callers of the read_objects method expect the data to be not nil
      basic_info["data"] = ""
    end

    basic_info
  end

  def map_trailers(trailers)
    trailers.group_by { |trailer| trailer.key.downcase }.transform_keys(&:downcase).transform_values do |trailers|
      # Normalize whitespaces e.g. `hello\r\n     world` to `hello world`
      trailers.map { |trailer| trailer.value.to_s.split("\n").map(&:strip).join(" ") }
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
      "message_truncated" => obj.truncated,
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
    # Normalize name e.g. convert ` "John Doe" ` to `John Doe`
    name = attribution.name.to_s.dup.gsub(/\A\s*"(.*)"\s*\z/, '\1')

    # Normalize email e.g. convert ` monalisa@github.com... ` to `monalisa@github.com`
    email = attribution.email.to_s.dup.strip.gsub(/\.+\z/, "")

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
                        "type" => SpokesAPI::Util.object_type_to_str(tree_entry.object.type),
                      }
                    end
    }
  end

  def map_blob(obj)
    blob_hash = {
      "oid" => obj.object.oid.id,
      "type" => "blob",
      "size" => obj.object.size,
      "truncated" => obj.truncated,
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
    tag_object = {
      "oid"           => obj.object.oid.id,
      "type"          => "tag",
      "name"          => obj.tag_object.name,
      "message_shas"  => map_expanded_oids(obj.tag_object.message_oids),
      "has_signature" => obj.tag_object.signature != "",
      "tagger"        => map_attribution(obj.tag_object.tagger, nil),
      "target"        => obj.tag_object.target.oid.id,
      "target_type"   => SpokesAPI::Util.object_type_to_str(obj.tag_object.target.type)
    }

    data_encoded = obj.tag_object.message.dup
    encoding = GitRPC::Encoding.detectable?(data_encoded) ? GitRPC::Encoding.guess(data_encoded)[:encoding] : GitRPC::Encoding::UTF8
    GitRPC::Encoding.tag_compatible(data_encoded, encoding)
    tag_object["message"] = data_encoded

    tag_object
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

  def read_object_headers(oids)
    return [] if oids.empty?

    # ensure each OID is valid
    oids.each do |oid|
      GitRPC::Util.ensure_valid_full_oid(oid)
    end

    object_headers = []

    oids.each_slice(SpokesAPI::Client::RESOLVE_OBJECT_BATCH_SIZE).each do |batch|
      headers = self.spokes_api.resolve_objects(oids: batch)
      batch.zip(headers.items).each do |oid, object_header|
        if object_header.error != ""
          raise GitRPC::ObjectMissing.new(oid, object_header.error)
        end

        object_headers << { "type" => SpokesAPI::Util.object_type_to_str(object_header.object&.type), "size" => object_header.object&.size }
      end
    end

    object_headers
  end

  # Public: Create a merge commit
  #
  # base           - the commit to merge into
  # head           - the commit to merge
  # author         - author information hash
  # commit_message - the message to use for the commit
  def create_merge_commit(base, head, author, commit_message, options = {}, &block)
    options = options.merge(use_tmp_objdir_mode: "migrate-on-success")

    if repository.feature_flag_enabled_or_raise?(:tmp_objdir_experiment) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      options = options.merge(dogstats: true)
      options[:use_tmp_objdir_mode] = "pack-and-migrate-on-success" if repository.feature_flag_enabled_or_raise?(:tmp_objdir_experiment_pack) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
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

  def diff_summary_cached?(commit1_oid, commit2_oid, base_commit_oid, algorithm: DIFF_SUMMARY_DEFAULT_ALGORITHM)
    max_deltas = GitRPC::Diff::DiffTreeParser::MAX_FILES
    ignore_whitespace = algorithm == GitRPC::Diff::ALGORITHM_IGNORE_WHITESPACE
    key = content_cache_key("read-diff-summary-truncated", "v1", commit1_oid, commit2_oid, base_commit_oid, ignore_whitespace, max_deltas)
    GitHub.cache.exist?(key)
  end

  def read_diff_summary(commit1_oid, commit2_oid, base_commit_oid, commit1_repo: nil, commit2_repo: nil, timeout: DIFF_SUMMARY_TIMEOUT, algorithm: DIFF_SUMMARY_DEFAULT_ALGORITHM)
    ignore_whitespace = algorithm == GitRPC::Diff::ALGORITHM_IGNORE_WHITESPACE

    GitRPC::Util.ensure_valid_full_oid(commit2_oid)
    GitRPC::Util.ensure_valid_full_oid(commit1_oid) if commit1_oid
    GitRPC::Util.ensure_valid_full_oid(base_commit_oid) if base_commit_oid

    timeout_key = content_cache_key("read-diff-summary", "v1", commit1_oid, commit2_oid, base_commit_oid, ignore_whitespace, "timed-out")
    previous_timeout = GitHub.cache.fetch(timeout_key) { nil }

    if previous_timeout && timeout <= previous_timeout
      return GitRPC::Diff::Summary.unavailable(reason: "timeout", error: nil)
    end

    client = self.spokes_api(timeout: timeout)
    begin
      max_deltas = GitRPC::Diff::DiffTreeParser::MAX_FILES
      # Truncate before caching to avoid unnecessary cache bloat
      key = content_cache_key("read-diff-summary-truncated", "v1", commit1_oid, commit2_oid, base_commit_oid, ignore_whitespace, max_deltas)
      data = cache_fetch(key, backend_method: :read_diff_summary) do
        client_response, contains_status = client.read_diff_summary(commit1_oid:, commit2_oid:, base_commit_oid:, commit1_repo:, commit2_repo:, ignore_whitespace:)
        {
          contains_status: contains_status,
          additions: client_response.stat.additions,
          deletions: client_response.stat.deletions,
          changed_files: client_response.stat.changed_files,
          deltas: client_response.deltas.take(max_deltas).map do |delta|
            d = delta.delta
            resp = {
              old_file: {
                oid: d.old_tree_node.object.oid.id,
                mode: "%06o" % d.old_tree_node.mode.mode,
                path: d.old_tree_node.path.name,
              },
              new_file: {
                oid: d.new_tree_node.object.oid.id,
                mode: "%06o" % d.new_tree_node.mode.mode,
                path: d.new_tree_node.path.name,
              },
              similarity: d.similarity,
              status: d.diff_status.to_s.delete_prefix("DIFF_STATUS_").upcase[0],
            }
            changes = if delta.text_changes
              { additions: delta.text_changes.additions, deletions: delta.text_changes.deletions }
            elsif delta.binary_changes
              { additions: nil, deletions: nil }
            else
              nil
            end
            resp.update(changes) if changes
            resp
          end
        }
      end
      null_oid = nil

      deltas = data[:deltas].flat_map do |d|
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
        if GitHub::Unsullied::Page.valid_page_name?(filename)
          commit_oids << commit_oid
        end
      end

      commits = {}
      self.read_objects(
        commit_oids.uniq,
        :commit
      ).each do |commit|
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
    if self.id
      refnames.each_slice(SpokesAPI::Client::resolve_references_ref_limit).flat_map do |batch|
        self.spokes_api.resolve_references(batch)
      end
    else
      self.rpc.read_qualified_refs(refnames, do_cache: true)
    end
  end

  # Public: show only commits reachable from <ref> that are not reachable from any other branch
  #
  # ref     - a ref
  # exclude - exclude commits that are reachable from any oid in this array
  # count   - count the commits instead of listing them
  #
  # Returns an array of commit oid strings, or an integer if count == true.
  # Raises GitRPC::CommandFailed on failure.
  def distinct_commits(ref, options = {})
    if self.feature_flag_enabled_or_raise?(:spokes_migrate_distinct_commits) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      self.distinct_commits_spokes(ref, options)
    else
      science "spokes_migrate_distinct_commits" do |e|
        e.context({
          repository: self,
          ref: ref,
          options: options
        })
        e.use do
          self.rpc.distinct_commits(ref, options)
        end

        e.try do
          self.distinct_commits_spokes(ref, options)
        end

        e.compare_errors do |control, candidate|
          if candidate.class == SpokesAPI::ResourceExhausted
            # Ignore resource exhausted errors
            true
          elsif control.class == GitRPC::CommandFailed && control.message.include?("bad object") && candidate.class == SpokesAPI::NotFound
            true
          else
            control == candidate
          end
        end

        e.compare do |control, candidate|
          if options[:count]
            control == candidate
          else
            control.sort == candidate.sort
          end
        end
      end
    end
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

  # Internal: map a string representation of object type to its SpokesAPI type
  def map_type_str(type)
    case type.to_s
    when "blob"
      :TYPE_BLOB
    when "tree"
      :TYPE_TREE
    when "commit"
      :TYPE_COMMIT
    when "tag"
      :TYPE_TAG
    when ""
      nil
    else
      raise ArgumentError, "invalid type #{type.inspect}"
    end
  end

  def distinct_commits_spokes(ref, options = {})
    oid = nil
    match = ref.match(/\A(?<ref>.+)@\{(?<oid>[0-9A-Fa-f]+)\}\Z/)
    if match
      ref = match[:ref]
      oid = match[:oid]
    end

    if options[:count]
      self.spokes_api.count_distinct_commits(ref: ref, oid: oid, exclude_oids: options[:exclude] || [])
    else
      SpokesAPI::Client.paged_responses do |cur|
        self.spokes_api.list_distinct_commits(ref: ref, oid: oid, exclude_oids: options[:exclude] || [], cursor: cur)
      end.flat_map do |response|
        response.commits.map { |item| item.oid.id }
      end
    end
  end
end
