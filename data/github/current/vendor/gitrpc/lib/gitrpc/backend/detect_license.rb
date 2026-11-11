# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "licensee"

module GitRPC
  # Git-based project removing the Rugged dependency
  #
  # Analyze a given (bare) Git repository for license information
  #
  # Project files for this project type will contain the following keys:
  #  :name - the file's path relative to the repo root
  #  :oid  - the file's OID
  class GitProjectNoRugged < Licensee::Projects::Project
    attr_reader :revision

    def initialize(backend, repo, revision: nil, **args)
      @backend = backend
      @raw_repo = repo
      @revision = revision

      super(**args)
    end

    private

    # Retrieve a file's content from the Git database
    #
    # file - the file hash, including the file's OID
    #
    # Returns a string representing the file's contents
    def load_file(file)
      res = @backend.spawn_git("cat-file", [file[:type], file[:oid]])
      if res["ok"]
        res["out"]
      else
        raise GitRPC::CommandFailed.new(res)
      end
    end

    # Returns an array of hashes representing the project's files.
    # Hashes will have the the following keys:
    #  :name - the file's path relative to the repo root
    #  :oid  - the file's OID
    def files
      @files ||= files_from_tree(@revision)
    end

    def files_from_tree(tree)
      args = ["-z", "--", tree]

      if tree.nil? || tree.empty?
        return []
      end

      res = @backend.spawn_git("ls-tree", args, nil, {})
      raise GitRPC::CommandFailed.new(res) if !res["ok"]

      files = []
      outlines = res["out"].split("\0")
      outlines.each do |outline|
        others, path = outline.split("\t", 2)
        entry = others.split(" ")
        if entry[1] == "blob"
          files << { :name => path, :oid => entry[2], :type => entry[1] }
        end
      end

      files
    end
  end

  class Backend
    rpc_reader :detect_license
    def detect_license(commit_oid)
      project = get_project revision: commit_oid
      project.license ? project.license.key : "no-license"
    end

    rpc_reader :detect_licenses
    def detect_licenses(commit_oid)
      project = get_project revision: commit_oid
      license_files_with_keys = project.license_files.map do |file|
        filepath = File.join(file.directory, file.filename)
        { filepath: filepath, license_key: file.license.key }
      end
      # Structured the return value this way in case we need to include additional data in the future.
      # For example, at some point we may want to detect license expression (i.e. "MIT and GPL-3.0") or additional more-complex cases.
      { licenses: license_files_with_keys }
    end

    private

    def get_project(revision:)
      GitRPC::GitProjectNoRugged.new(self, @repo, revision: revision)
    end
  end
end
