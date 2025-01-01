# typed: true
# frozen_string_literal: true

class Api::RepositoryContents < Api::App
  include ReceiveSchemaWithOpenApi
  include ActionView::Helpers::TextHelper, ActionView::Helpers::TagHelper,
    TextHelper, BasicHelper, BlobMarkupHelper, Api::App::RepositoryContentHelpers,
    Api::App::GitActorHelpers

  include Api::App::RepositoryContentsDependency
  include Api::App::RepositoryRulesDependency

  RAW_OBJECT_ONLY_BLOB_SIZE = 1.megabyte
  MAX_BLOB_SIZE = 100.megabyte

  # Get a readme in a repo
  get %r{/repositories/(\d+)/readme(?:/(.*))?}, operation_ids: ["repos/get-readme", "repos/get-readme-in-directory"] do |_repository_id, path|
    if path
      @operation = @operations["repos/get-readme-in-directory"]
    else
      @operation = @operations["repos/get-readme"]
    end

    @route_owner       = @operation.route_owner
    @documentation_url = @operation.documentation_url

    begin
      @content_path = path

      control_access :get_readme,
        resource: current_repository,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      if current_repository.empty? || tree_name.blank?
        deliver_error!(404)
      end

      if readme
        last_modified = calc_last_modified_for_object(current_commit)

        set_caching_headers!({ etag: readme.oid, last_modified: last_modified })

        if medias.api_param?(:raw)
          deliver_raw readme.data, content_type: "#{medias}; charset=utf-8"
        elsif medias.api_param?(:html)
          if readme.binary?
            deliver_error!(422, message: "We can’t display this README as HTML because it appears to contain binary data.")
          end

          if source = readme.symlink_source
            readme.info["path"] = source.path
          end

          deliver_raw render_file(readme, readme.path), { content_type: "#{medias}; charset=utf-8" }
        else
          if source = readme.symlink_source
            readme.info["sha"] = source.oid
            readme.info["path"] = source.path
          end

          deliver :content_hash, readme, { repo: current_repository, full: true, ref: tree_name }
        end
      else
        deliver_error(404)
      end
    rescue GitRPC::NoSuchPath
      deliver_error(404)
    end
  end

  # Get a repository's license
  get "/repositories/:repository_id/license", operation_id: "licenses/get-for-repo" do |_repository_id|
    control_access :get_license,
      resource: current_repository,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) if current_repository.empty? || tree_name.blank?
    deliver_error!(404) unless current_repository.license && license

    if medias.api_param?(:raw)
      deliver_raw license.data,
        content_type: "#{medias}; charset=utf-8",
        last_modified: calc_last_modified_for_object(current_commit)
    elsif medias.api_param?(:html)
      deliver_raw render_file(license, license.path),
        content_type: "#{medias}; charset=utf-8",
        last_modified: calc_last_modified_for_object(current_commit)
    else
      deliver :license_content_hash, license,
        repo: current_repository,
        full: true,
        last_modified: calc_last_modified_for_object(current_commit),
        ref: tree_name,
        default_branch: default_branch
    end
  end

  # Get a specific file or directory in a repo
  get "/repositories/:repository_id/contents/?*", operation_id: "repos/get-content" do
    control_access_remote :get_contents,
      resource: current_repository,
      path: content_path,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    serve_contents_with_spokes!
  end

  after "/repositories/:repository_id/contents/?*" do
    next unless T.unsafe(self).request.get?
    response = T.unsafe(self).response
    request = T.unsafe(self).request

    if T.unsafe(self).current_repository&.feature_enabled?(:repos_contents_hydro_publish)
      Repositories::ExperimentResponseHydroPublisher.publish(
        route: "/repositories/:repository_id/contents/?*",
        request: request,
        response: response,
      )
    end
  end

  after "/repositories/:repository_id/contents/?*" do
    next unless T.unsafe(self).current_repository&.feature_enabled?(:reposd_contents_experiment)
    next unless T.unsafe(self).request.get?
    next if T.unsafe(self).medias.api_param?(:html)
    next if T.unsafe(self).request_elapsed_time > 5 # don't run the experiment if the request has already taken a long time

    if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      # skip the experiment in test if we're not running reposd
      next unless TestServices::Reposd.start_reposd?
    end

    response = T.unsafe(self).response

    T.unsafe(self).science("reposd_contents") do |e|
      e.context({
        name_with_owner: T.unsafe(self).current_repository.name_with_display_owner,
        request_id: T.unsafe(self).request_id,
      })

      e.use do
        resp_body = response.body
        resp_body = resp_body.first if resp_body.is_a?(Array)
        clean_body = T.unsafe(self).clean_response_body(resp_body, response.headers)

        {
          status: response.status,
          headers: response.headers.except(*Repositories::ExperimentResponseHydroPublisher::EXCLUDED_RESPONSE_HEADERS).sort.to_h,
          body: Digest::SHA256.base64digest(clean_body || ""),
        }
      end

      e.try do
        reposd_response = T.unsafe(self).query_reposd(request: T.unsafe(self).request)
        clean_body = T.unsafe(self).clean_response_body(reposd_response.body, response.headers)

        {
          status: reposd_response.status,
          headers: reposd_response.headers.sort.to_h,
          body: Digest::SHA256.base64digest(clean_body || ""),
        }
      end
    end
  end

  # Create or replace a file in a repo
  put %r{/repositories/(\d+)/contents/(.+)}, operation_id: "repos/create-or-update-file-contents" do |_repository_id, path|
    repo = current_repository

    control_access :update_file, resource: repo, path: path, allow_integrations: true, allow_user_via_granular_actor: true
    ensure_repo_writable!(repo)

    if message = validate_path(path)
      deliver_error! 422,
        message: "path #{message}",
        errors: [api_error(:Commit, :path, :invalid)]
    end

    data = receive(Hash, required: true) || {}
    attributes = attr(data, :message, :content, :branch, :author, :committer, :sha)

    # We need the oid/sha of the file for authentication check to work properly in case of missing workflow scope
    oid = attributes["sha"] || Rugged::Repository.hash_data(decode_content(attributes["content"]), :blob)
    ensure_file_writable!(repo, path, oid)

    branch = (attributes["branch"] || repo.default_branch).to_s
    file_present = repo.includes_file?(path, branch)
    update = file_present
    create = !update
    action = create ? "create" : "update"

    ensure_data_satisfies_schema!(attributes, "file", action)

    # Determine whether the commit should be automatically signed by GitHub's
    # web committer.
    #
    # If the content creator is a bot and neither the committer nor the author
    # are specified, we can sign the commit with confidence. We're choosing
    # (for now) not to sign bot-created commits authored on behalf of a user.
    sign = GitHub.web_commit_signing_enabled? &&
      current_user.bot? &&
      attributes["author"].nil? &&
      attributes["committer"].nil?

    metadata = set_commit_metadata(attributes)

    # Remove the specified committer if we are to sign the commit. This
    # allows CommitsCollection#create to assign GitHub's web committer instead
    # of the current user.
    metadata.delete(:committer) if sign

    begin
      ref = if create && repo.heads.empty?
        repo.heads.find_or_build(branch)
      else
        repo.heads.find(branch)
      end

      deliver_error!(404, message: "Branch #{branch} not found") unless ref

      if create && !repo.valid_file_path?(path, branch)
        deliver_error!(409, message: "Sorry, a file exists where you’re trying to create a subdirectory. Choose a new path and try again.")
      end

      if update
        blob = repo.tree_entry(ref.target_oid, path)
        if !blob.blob?
          deliver_error!(422, message: "#{path} is not a file")
        end
        blob_sha = attributes["sha"]
        if blob_sha != blob.sha
          deliver_error!(409, message: "#{path} does not match #{blob_sha}")
        end
      end

      ref.append_commit(metadata, current_user, sign: sign, reflog_data: request_reflog_data("git repo contents api")) do |files|
        files.add(path, decode_content(attributes["content"]))
      end
    rescue Git::Ref::HookFailed => e
      deliver_error!(409, message: "Could not #{action} file because a Git pre-receive hook failed.\n\n#{e.message}")
    rescue Git::Ref::ProtectedBranchUpdateError => e
      deliver_error!(409, {
        message: "Could not #{action} file: #{e.result.message}",
        documentation_url: "#{GitHub.help_url}/articles/about-protected-branches",
      })
    rescue Git::Ref::RepositoryRuleViolationError => e
      halt deliver_rule_violation_error(e, 409)
    rescue Git::Ref::ComparisonMismatch => e
      deliver_error!(409, message: e.message)
    rescue GitRPC::BadGitmodules, GitRPC::SymlinkDisallowed => e
      deliver_error!(422, message: e.message)
    rescue Git::Ref::WorkflowUpdatePolicyError => e
      deliver_error!(403, message: e.message)
    rescue GitRPC::RequestTooLarge
      deliver_error!(422,
        message: "Sorry, the file is too large to be processed. Consider creating/updating the file in a local clone " \
        "and pushing it to GitHub."
      )
    rescue GitHub::DGit::UnroutedError,
           GitHub::DGit::InsufficientQuorumError,
           GitHub::DGit::ThreepcFailedToLock
      deliver_error!(503, message: "Could not create file. Please try again later.")
    end

    content = content_at(repo, ref.target.tree_oid, path)

    GitHub.dogstats.increment("file", tags: ["via:api", "action:#{action}"])

    options = {
      content: content,
      commit: ref.target,
      ref: branch,
    }
    deliver :contents_crud_hash, options,
      repo: repo,
      status: create ? 201 : 200
  end

  # Delete a file in a repo
  delete %r{/repositories/(\d+)/contents/(.+)}, operation_id: "repos/delete-file" do |_repository_id, path|
    repo = current_repository

    control_access :delete_file, resource: repo, path: path, allow_integrations: true, allow_user_via_granular_actor: true
    ensure_repo_writable!(repo)

    if message = validate_path(path)
      deliver_error! 422,
        message: "path #{message}",
        errors: [api_error(:Commit, :path, :invalid)]
    end

    data = receive(Hash, required: false) || {}
    attributes = attr(data, :message, :content, :branch, :author, :committer, :sha)

    # Most HTTP tooling doesn't support DELETE with body so we need to look for
    # required params in the query, too.
    attributes = attributes.merge(commit_params_from_query)

    branch = (attributes["branch"] || repo.default_branch).to_s
    file_present = repo.includes_file?(path, branch)

    ensure_data_satisfies_schema!(attributes, "file", "delete")
    if !repo.heads.exist?(branch) && !repo.heads.empty?
      deliver_error!(404, message: "Branch #{branch} not found")
    end
    deliver_error!(404) unless file_present

    metadata = set_commit_metadata(attributes)

    begin
      ref = repo.heads.find(branch)

      deliver_error!(404, message: "Branch #{branch} not found") unless ref

      blob = repo.tree_entry(ref.target_oid, path)
      if !blob.blob?
        deliver_error!(422, message: "#{path} is not a file")
      end
      blob_sha = attributes["sha"]
      if blob_sha != blob.sha
        deliver_error!(409, message: "#{path} does not match #{blob_sha}")
      end

      ref.append_commit(metadata, current_user, reflog_data: request_reflog_data("git repo contents api")) do |files|
        files.remove(path)
      end
    rescue Git::Ref::HookFailed => e
      deliver_error!(409, message: "Could not delete file because a Git pre-receive hook failed.\n\n#{e.message}")
    rescue Git::Ref::ProtectedBranchUpdateError => e
      deliver_error!(409, {
        message: "Could not delete file: #{e.result.message}",
        documentation_url: "#{GitHub.help_url}/articles/about-protected-branches",
      })
    rescue Git::Ref::RepositoryRuleViolationError => e
      deliver_error!(409, message: e.detailed_message)
    rescue Git::Ref::ComparisonMismatch,
           Git::Ref::InvalidName,
           Git::Ref::UpdateFailed => e
      deliver_error!(409, message: e.message)
    rescue GitRPC::Failure,
           GitRPC::BadGitmodules,
           GitRPC::SymlinkDisallowed => e
      deliver_error!(422, message: e.message)
    rescue GitHub::DGit::UnroutedError,
           GitHub::DGit::InsufficientQuorumError,
           GitHub::DGit::ThreepcFailedToLock
      deliver_error!(503, message: "Could not delete file. Please try again later.")
    end

    GitHub.dogstats.increment("file", tags: ["via:api", "action:delete"])

    options = {
      content: nil,
      commit: ref.target,
      ref: branch,
    }
    deliver :contents_crud_hash, options,
      repo: repo,
      status: 200
  end

  # Get a tarball link
  get %r{/repositories/(\d+)/tarball(?:/(.*))?}, skip_rate_limit: true, operation_id: "repos/download-tarball-archive" do |_repository_id, rev|
    control_access :get_archive_link,
      resource: current_repository,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    @revision = rev
    codeload "legacy.tar.gz", "#{base_url}/#{current_repository.name_with_owner_for_api}/tarball"
  end

  # Get a zipball link
  get %r{/repositories/(\d+)/zipball(?:/(.*))?}, skip_rate_limit: true, operation_id: "repos/download-zipball-archive" do |_repository_id, rev|
    control_access :get_archive_link,
      resource: current_repository,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    @revision = rev
    codeload "legacy.zip", "#{base_url}/#{current_repository.name_with_owner_for_api}/zipball"
  end

  READ_ONLY_ACTION_ROUTES = [
    ["get", "\\/repositories\\/(\\d+)\\/tarball(?:\\/(.*))?"],
    ["get", "\\/repositories\\/(\\d+)\\/zipball(?:\\/(.*))?"]
  ]

  # This method is defined here to allow the ConditionalAccess
  # enforcer to skip access checks (specifically IP allow list) on
  # public repositories.
  def action
    return :read if READ_ONLY_ACTION_ROUTES.include?(
      [request.request_method.downcase, route_pattern.to_s]
    )
    nil
  end

  private

  def commit_params_from_query
    params = request.params

    data = {}

    data.update("message" => params["message"]) if params.key?("message")
    data.update("sha" => params["sha"]) if params.key?("sha")
    data.update("branch" => params["branch"]) if params.key?("branch")

    author = {
      "name"  => params["author.name"],
      "email" => params["author.email"],
    }
    data.update("author" => author) if author.values.any?

    committer = {
      "name"  => params["committer.name"],
      "email" => params["committer.email"],
    }
    data.update("committer" => committer) if committer.values.any?

    data
  end

  def render_file(readme, path, id = "readme")
    content = format_readme(readme, relative_paths: true)
    ext = File.extname(readme.name).sub(".", "")
    content_tag :div, content.html_safe, # rubocop:disable Rails/OutputSafety
      :id => id,
      :class => ext,
      "data-path" => "#{h(path)}"
  end

  def base_url
    GitHub.url
  end

  def codeload(type, alt_prefix)
    unless current_repository.public?
      current_repository.instrument :download_zip
    end

    ac = current_repository.archive_command(branch_to_archive, type)
    url = ac.codeload_url(current_user)

    expires 0, :public, :must_revalidate
    redirect url
  rescue GitRepository::ArchiveCommand::RefnameConflictError => e
    # Regenerate the links the caller could have provided to not be ambiguous
    variants = e.variants.map do |variant|
      "#{alt_prefix}/#{variant.qualified_name}"
    end

    variants.each do |refname|
      @links.add(refname, rel: ALTERNATE_RELATION)
    end
    deliver_error!(300, message: "'#{@revision}' has multiple possibilities: #{variants.join(", ")}")
  end

  def branch_to_archive
    # Check if the requested branch/tree/commit exists:
    rev = GitRepository::ArchiveCommand.qualified_name_from_revision(current_repository, @revision) || @revision
    if current_repository.refs.find(rev)
      # Even if a branch is renamed, if a new branch with the old name has since been created,
      # favor it over the redirect
      rev
    else
      # Check if we know the requested branch was renamed:
      rename = current_repository.branch_rename_for(old_name: rev)
      return rev unless rename

      # Branch was renamed, so load the new branch:
      rename.new_name
    end
  end

  # Internal: set the metadata for the generated commit
  #
  # see CommitsCollection#create for the necessary data
  #
  # Returns a Hash of commit metadata
  def set_commit_metadata(attributes)
    metadata = {
      message: attributes["message"],
      committer: current_user,
      author: current_user,
    }

    log_data[:commit_metadata_keys] = []

    if attributes["committer"]
      committer = git_actor!(attributes, key: "committer")
      metadata[:committer] = committer.to_gitrpc_hash.symbolize_keys
      metadata[:author] = committer.to_gitrpc_hash.symbolize_keys
      log_data[:commit_metadata_keys] << "committer"
    end

    if attributes["author"]
      author = git_actor!(attributes, key: "author")
      metadata[:author] = author.to_gitrpc_hash.symbolize_keys
      log_data[:commit_metadata_keys] << "author"
    end

    metadata
  end

  # Internal: Gets the tags to send for this blob for Datadog metrics.
  # Returns an array of tags as strings.
  def get_blob_tags(success, blob_size, medias)
    tags = ["success:#{success}"]

    case blob_size
    when 0...RAW_OBJECT_ONLY_BLOB_SIZE
      tags.push("blob_size:0_1MB")
    when RAW_OBJECT_ONLY_BLOB_SIZE...MAX_BLOB_SIZE
      tags.push("blob_size:1_100MB")
    else
      tags.push("blob_size:over_100MB")
    end

    if medias.api_param?(:raw)
      tags.push("media_type:raw")
    elsif medias.api_param?(:html)
      tags.push("media_type:html")
    else
      tags.push("media_type:object")
    end
  end

  # Internal: decode the content from Base64
  #
  # Delivers an error (422) if the input is not valid Base64
  #
  # Returns a decoded String of content
  def decode_content(content)
    content ||= ""
    Base64.strict_decode64(content.gsub("\n", ""))
  rescue ArgumentError
    deliver_error!(422, message: "content is not valid Base64")
  end

  # Internal: deliver too large forbidden error.
  #
  # Delivers a 403 indicating the blob is too large to return. Provide alternative method for
  # obtaining the blob, depending on size.
  #
  # Delivers a 403 with explanation.
  def deliver_too_large_error!(blob_size)
    GitHub.dogstats.increment("repos.api.get_repo_contents", tags: get_blob_tags(false, blob_size, medias))

    if blob_size > RAW_OBJECT_ONLY_BLOB_SIZE && blob_size <= MAX_BLOB_SIZE
      message = "Either the raw or object media type must be used for this endpoint for blobs between 1-100 MB. "\
        "The raw type will return the file contents, and the JSON type will return the file's metadata. Please try "\
        "again with a valid media type."
    else
      message = "This endpoint can only return blobs smaller than 100 MB in size. The requested blob is too large "\
        "to fetch via the API, but you can always clone the repository via Git to obtain it."
    end

    deliver_error! 403,
      message: message,
      errors: [api_error(:Blob, :data, :too_large)],
      documentation_url: "/rest/reference/repos#get-repository-content"
  end
end
