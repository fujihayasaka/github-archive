# typed: true
# frozen_string_literal: true

class Api::GitTrees < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::App::RepositoryContentsDependency

  MAX_TREE_LIMIT = 7.megabyte.freeze

  include Api::App::ContentHelpers

  # just so I have something to serialize
  class Tree
    attr_accessor :sha, :entries
    attr_writer :truncated
    def initialize(sha, entries, truncated)
      @sha = sha
      @entries = entries
      @truncated = truncated
    end

    def truncated
      !!@truncated
    end
  end

  # Valid Git tree object file modes:
  #   https://developer.github.com/v3/git/trees/#create-a-tree

  VALID_TREE_MODES = ["100644", # file (blob)
                      "100755", # executable (blob)
                      "040000", # subdirectory (tree)
                      "160000", # submodule (commit)
                      "120000"] # blob that specifies the path of a symlink

  # Get the contents of a tree object
  get "/repositories/:repository_id/git/trees/*", operation_id: "git/get-tree" do
    begin
      control_access :get_tree,
        resource: repo = find_repo!,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      ensure_repo_content!(repo)
      tree_ref = params[:splat].first
      sha = repo.ref_to_sha(tree_ref)
      deliver_error!(404) unless sha
      # if fetched by SHA, direct the client to cache this longer
      # since a git OID always refers to the same immutable object
      max_age = if tree_ref == sha
        86400 # one day in seconds
      else
        nil
      end
      truncated = false

      if params[:recursive]
        result = repo.rpc.ls_tree(sha, long: true, recurse: true, show_trees: true, byte_limit: MAX_TREE_LIMIT)
        truncated = result["truncated"]

        entries = []
        result["entries"].each do |entry|
          entries << TreeEntry.from_ls_tree(repo, entry, from_collection: true)
        end
      else
        _oid, entries, truncated = repo.tree_entries(sha, "", recursive: params[:recursive], limit: 100_000, skip_size: false)
      end
      deliver_error!(404) if entries.size == 0
      GitHub.dogstats.histogram("git_trees#{params[:recursive] && "_recursive"}.entry_count", entries.size, tags: ["via:api"])

      tree = Api::GitTrees::Tree.new(sha, entries, truncated)
      deliver :api_git_trees_tree_hash, tree,
        repo: repo,
        last_modified: calc_last_modified_for_object(repo),
        max_age: max_age
    rescue GitRPC::ObjectMissing
      deliver_error!(404)
    rescue GitRPC::InvalidObject
      deliver_error!(422,
        message: "Invalid object requested. SHA must identify a commit or a tree.",
        documentation_url: @documentation_url)
    # Doing this here isn't great. The recursive fetching should probably be pushed back down into
    # TreeListable#tree_entries so it can raise the same GitRPC::InvalidObject for both cases.
    rescue GitRPC::CommandFailed => boom
      raise unless boom.message.include?("fatal: not a tree object")

      deliver_error!(422,
        message: "Invalid object requested. SHA must identify a commit or a tree.",
        documentation_url: @documentation_url)
    end
  end

  # Get a full list of all files in a tree.  Faster than get-tree and not
  # subject to truncation but less flexible (just a list of strings
  # representing blob paths)
  get "/repositories/:repository_id/git/tree-file-list/*", operation_id: :internal do
    control_access :get_tree,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_repo_content!(repo)
    tree_ref = params[:splat].first
    sha = repo.ref_to_sha(tree_ref)
    deliver_error!(404) unless sha

    # if fetched by SHA, direct the client to cache this longer
    # since a git OID always refers to the same immutable object
    max_age = if tree_ref == sha
      86400 # one day in seconds
    else
      nil
    end

    # Give Sinatra a chance to halt immediately if ETag matches.
    set_caching_headers!({ etag: sha, max_age: max_age })

    result = begin
      repo.rpc.tree_file_list(sha)
    rescue GitRPC::ObjectMissing
      deliver_error!(404)
    rescue GitRPC::InvalidObject
      deliver_error!(422, message: "Invalid object requested. SHA must identify a commit or a tree.")
    end

    deliver_raw(result.to_json, content_type: "application/json; charset=utf-8")
  end

  # Create a new tree object
  post "/repositories/:repository_id/git/trees", operation_id: "git/create-tree" do
    control_access :create_tree,
      resource: repo = find_repo!,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    ensure_repo_content!(repo)
    ensure_repo_writable!(repo)

    # Introducing strict validation of the git-tree.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("git-tree", "create", skip_validation: true)
    tree = Array(data["tree"])

    if tree.blank?
      deliver_error!(422,
        message: "Invalid tree info",
        documentation_url: @documentation_url)
    end

    write_tree = tree.each.with_object({}) do |entry, entries|
      validate_tree_entry(entry, repo)

      if delete_entry?(entry)
        entries[entry["path"]] = nil
      else
        oid = entry["sha"] || Rugged::Repository.hash_data(entry["content"], :blob)
        ensure_file_writable!(repo, entry["path"], oid) if RefUpdates::WorkflowUpdatesPolicy::FileUpdate.new(entry["path"], oid).workflow_file?
        entries[entry["path"]] = {
          "oid"    => entry["sha"],
          "data"   => entry["content"],
          "source" => entry["source"],
          "mode"   => entry["mode"].to_i(8),
        }
      end
    end

    if data["base_tree"]
      tree_oid = resolve_treeish(repo, data["base_tree"])

      if tree_oid.nil?
        deliver_error!(422,
          message: "base_tree is not a valid tree oid",
          documentation_url: @documentation_url)
      end
    end

    timeout_before = repo.rpc.options[:timeout]
    sha = begin
      event = RuleEngine::Events::PreBlobEvent.new(
        repo,
        current_user,
        metadata: {
          blobs: write_tree.map do |path, entry|
            [path, entry&.fetch("data", nil)]
          end.to_h
        }
      )

      rule_suite = T.must(RuleEngine::GenericEvaluator.evaluate_rules(event).first)

      raise Git::Ref::RepositoryRuleViolationError.new(rule_suite) unless rule_suite.action_permitted?

      repo.rpc.options[:timeout] = safe_time_limit
      repo.rpc.create_tree(write_tree, tree_oid)
    rescue GitRPC::BadObjectState => e
      deliver_error!(422,
        message: e.to_s,
        documentation_url: @documentation_url)
    rescue GitRPC::BadGitattributes, GitRPC::BadGitmodules, GitRPC::SymlinkDisallowed, GitRPC::InvalidObject => e
      deliver_error!(422,
                     message: e.to_s,
                     documentation_url: @documentation_url)
    rescue GitRPC::Timeout
      deliver_error!(422,
                     message: "Sorry, your request timed out.  It's likely that your input " \
                              "was too large to process.  Consider building the tree incrementally, " \
                              "or building the commits you need in a local clone of the repository " \
                              "and then pushing them to GitHub.",
                     documentation_url: @documentation_url)
    rescue GitRPC::RequestTooLarge
      deliver_error!(422,
        message: "Sorry, your input was too large to process.  Consider building the tree " \
                 "incrementally, or building the commits you need in a local clone of the repository " \
                 "and then pushing them to GitHub.",
        documentation_url: @documentation_url)
    rescue Git::Ref::RepositoryRuleViolationError => e
      deliver_error!(422, message: e.detailed_message)
    ensure
      repo.rpc.options[:timeout] = timeout_before
    end

    _, entries, truncated = repo.tree_entries(sha, "", skip_size: false)
    tree = Api::GitTrees::Tree.new(sha, entries, truncated)
    deliver_error!(404) if tree.entries.size == 0
    deliver :api_git_trees_tree_hash, tree,
      repo: repo,
      status: 201
  end

  private

  # A value less than the total request timeout suitable for use as a
  # downstream timeout value; it should be able to elapse while leaving enough
  # margin to handle request cleanup if it's exceeded.
  def safe_time_limit(margin: 2)
    computed_limit = request_time_left - margin
    computed_limit.positive? ? computed_limit : 0.1 # don't return a negative limit
  end

  def request_time_left
    start_time = request.env["process.request_start"] || Process.clock_gettime(Process::CLOCK_MONOTONIC)
    GitHub.request_timeout(request.env) - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
  end

  def resolve_treeish(repo, treeish)
    return nil unless sha = repo.ref_to_sha(treeish)

    case object = repo.objects.read(sha)
    when ::Tree
      object.oid
    when ::Commit
      object.tree_oid
    end
  rescue GitRPC::ObjectMissing
    nil
  end

  def validate_tree_entry(entry, repo)
    if !entry.is_a?(Hash)
      deliver_error! 422, message: "Invalid tree info"
    end

    if path = entry["path"].to_s
      entry["path"] = path.gsub("\0", "")
    end

    entry["sha"] = nil if !entry["sha"].nil? && entry["sha"].blank?

    validate_tree_path(entry)
    validate_tree_has_sha_or_content(entry)
    validate_tree_has_valid_sha(entry, repo)
    validate_tree_mode(entry)
  end

  def validate_tree_path(entry)
    if message = validate_path(entry["path"])
      deliver_error! 422, message: "tree.path #{message}"
    end
  end

  # Each entry must provide content or a sha, but not both (xor).
  # If the sha is provided it must be a valid sha or `nil`,
  # indicating the file should be deleted
  def validate_tree_has_sha_or_content(entry)
    tree_entry_has_sha_param = entry.keys.include?("sha")
    tree_entry_has_content = !entry["content"].nil?

    if !(tree_entry_has_sha_param ^ tree_entry_has_content)
      deliver_error! 422, message: "Must supply either tree.sha or tree.content. Request will be rejected if both are present."
    end
  end

  def validate_tree_has_valid_sha(entry, repo)
    if invalid_sha?(entry, repo)
      deliver_error! 422,
        message: "tree.sha #{entry["sha"]} is not a valid #{entry["type"]}"
    end
  end

  def validate_tree_mode(entry)
    if !VALID_TREE_MODES.include?(entry["mode"])
      deliver_error! 422, message: "Must supply a valid tree.mode"
    end

    if entry["mode"] == "040000" && entry.has_key?("content")
      deliver_error! 422, message: "A subdirectory may not have content"
    end
  end

  def delete_entry?(entry)
    entry["sha"].nil? && entry["content"].nil?
  end

  def invalid_sha?(entry, repo)
    return if (sha = entry["sha"]).blank?

    # Only verify the format for commit entries (submodules)
    if entry["type"] == "commit"
      repo.objects.verify_sha_format(sha, true) # raises if SHA format invalid
      false
    else
      !repo.objects.exist?(sha, entry["type"])
    end
  rescue RepositoryObjectsCollection::InvalidObjectId
    true
  end
end
