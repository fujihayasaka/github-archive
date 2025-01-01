# typed: true
# frozen_string_literal: true

class Repository::TemplateInitializer
  attr_reader :repo

  def initialize(repo)
    @repo = repo
  end

  def perform
    return unless repo.created_by

    unless repo.fork?
      # Set the user's preferred default branch even if we're not creating any initial files:
      repo.update_default_branch_spokes("refs/heads/#{default_branch}")
    end

    files = generate_files
    return if files.empty?

    author = {
      "name" => repo.created_by.git_author_name,
      "email" => repo.created_by.git_author_email,
      "time" => Time.zone.now.iso8601,
    }

    committer = {
      "email" => GitHub.web_committer_email,
      "name"  => GitHub.web_committer_name,
      "time"  => author["time"],
    }

    info = {
      "message" => "Initial commit",
      "committer" => committer,
      "author" => author,
    }

    args = [nil, info, files]

    commit_oid = repo.rpc.create_tree_changes(*args, &repo.method(:sign_commit))
    repo.heads.build(default_branch).update(commit_oid, repo.created_by)

    true
  end

  def default_branch
    repo.owner_default_new_repo_branch
  end

  def generate_files
    files = {}

    if repo.auto_init?
      files["README.md"] = { "data" => generate_readme_content }
    end

    if repo.license_template.present?
      files["LICENSE"] = { "data" => generate_license_content }
    end

    if repo.gitignore_template.present?
      files[".gitignore"] = { "data" => generate_gitignore_content }
    end

    files
  end

  # Generates an initial license file using License#generate. See docs over
  # there for more info.
  #
  # Returns a string with the generated license data.
  def generate_license_content
    return if repo.license_template.nil?
    license = License[repo.license_template]
    license.generate(repository: repo) if license
  end

  def generate_readme_content
    repo.generate_readme
  end

  def generate_gitignore_content
    Gitignore.template(repo.gitignore_template)
  end
end
