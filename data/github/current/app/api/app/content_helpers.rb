# typed: false
# frozen_string_literal: true

module Api::App::ContentHelpers
  def current_repository
    @current_repository ||= find_repo!
  end

  def serve_contents(&block)
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do |_span|
      content_path

      if current_repository.empty?
        deliver_error!(404,
          message: "This repository is empty.",
          documentation_url: "/v3/repos/contents/#get-contents")
      end

      # handle paths that end in /
      redirect api_url(request.path[0..-2]) if content_path.ends_with?("/")

      gitrpc &block
    end
  end

  def gitrpc(&block)
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do |_span|
      begin
        block.call
      rescue GitRPC::ObjectMissing, GitRPC::InvalidObject, GitRPC::BadRepositoryState, GitRPC::NoSuchPath,
        GitRPC::InvalidRepository, GitHub::DGit::UnroutedError, GitHub::DGit::NotFoundError
        deliver_error!(404)
      end
    end
  end

  # todo: we are using this in RepositoryCommits as well
  def path_string(extra = nil)
    joined_path(extra) * "/"
  end

  def joined_path(extra = nil)
    path = [content_path, extra]
    path.flatten!
    path.compact!
    path
  end

  def parent_directory_path(path)
    dirname = File.dirname(path)
    dirname == "." ? "" : dirname
  end

  def content_path
    @content_path ||= params[:splat] ? params[:splat].first.to_s : ""
  end

  def default_branch
    @default_branch ||= current_repository.default_branch
  end

  def tree_name
    @tree_name ||= (params[:ref] || default_branch).try(:b)
  end

  def tree_sha
    @tree_sha ||= current_commit.try(:tree_oid)
  end

  # The current commit_sha based on the tree_name
  #
  #   Returns 404 immediately if no matching commit is found
  def commit_sha
    return @commit_sha if defined?(@commit_sha)

    load_commit

    @commit_sha
  end

  # The current commit based on the commit_sha
  #
  #   Returns 404 immediately if no matching commit is found
  def current_commit
    return @current_commit if defined?(@current_commit)

    load_commit

    @current_commit
  end

  # Attempt to resolve tree_name to a commit.
  def load_commit
    @commit_sha = current_repository.ref_to_sha(tree_name)
    @current_commit = current_repository.commits.find(@commit_sha) if @commit_sha
    true
  rescue GitRPC::ObjectMissing, GitRPC::InvalidObject
  ensure
    deliver_error!(404,
      message: "No commit found for the ref #{tree_name}",
      documentation_url: "/v3/repos/contents/") unless @current_commit
  end

  def current_directory
    @current_directory ||= current_repository.directory(commit_sha, path_string)
  end

  def content_at(repo, tree_sha, path)
    repo.tree_entry(tree_sha, path)
  rescue GitRPC::NoSuchPath
    nil
  end

  def submodule
    return @submodule if defined?(@submodule)

    content = content_at(current_repository, tree_sha, path_string)

    @submodule = if content && content.submodule?
      content.submodule =
        current_repository.submodule(commit_sha, path_string)
      content
    else
      nil
    end
  end

  def blob
    return @blob if defined?(@blob)

    @blob = current_repository.blob(tree_sha, path_string)
  end

  def tree_object(children)
    return @tree_object if defined?(@tree_object)

    @tree_object = if path_string.blank?
      TreeEntry.new(current_repository, {
        "type" => "tree",
        "oid"  => tree_sha,
        "path" => path_string,
      })
    else
      content_at(current_repository, tree_sha, path_string)
    end
  rescue GitRPC::InvalidObject
    @tree_object = nil
  end

  def tree
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do |_span|
      begin
        return @tree if defined?(@tree)

        @tree = current_repository.tree_entries(commit_sha, path_string, skip_size: false)[1].each do |entry|
          if entry.submodule?
            entry.submodule =
              current_repository.submodule(commit_sha, entry.path)
          end
        end
      rescue GitRPC::InvalidObject
        @tree = nil
      end
    end
  end

  def readme
    return @readme if defined?(@readme)

    @readme = current_directory.preferred_readme
  end

  def license
    return @license if defined?(@license)

    @license = current_repository.preferred_license(tree_name: tree_name)
  end

  def ref_sha_path_extractor
    @ref_sha_path_extractor ||= GitHub::RefShaPathExtractor.new(current_repository)
  end

  # Internal: Checks to see if a path is okay
  #
  # path - String containing the path to a file
  #
  # Returns a String message explaining the problem with the path.
  # Returns nil if the path is fine.
  def validate_path(path)
    GitHub::GitFile.validate_path(path)
  end
end
