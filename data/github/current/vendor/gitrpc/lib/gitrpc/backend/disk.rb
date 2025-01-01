# rubocop:disable Style/FrozenStringLiteralComment
require "fileutils"

# RPC calls for creating and initializing repositories and poking around
# inside the repository directory's files.
module GitRPC
  class Backend
    # Public: Create and initialize the repository on disk.
    #
    # :initial_branch is an optional String specifying the name for the initial
    # branch in the newly created repository. If nil, falls back to the default.
    #
    # Returns nothing.
    rpc_writer :init, no_git_repo: true
    def init(initial_branch: nil)
      # --template= skips (over)writing 'hooks/', 'info/exclude', and 'description'
      # since we don't need any of those files.
      opts = ["--bare", "--quiet", "--template="]
      opts << "--initial-branch=#{initial_branch}" if initial_branch && !initial_branch.empty?
      opts << path

      res = spawn_git("init", opts)
      raise GitRPC::Failure.new(GitRPC::CommandFailed.new(res)) if !res["ok"]
      nil
    end

    # Public: Like #init, but knows a couple other tricks, too.
    #
    # If the repository doesn't exist, create it.
    #
    # If :hooks_template exists, ensure the hooks directory is a symlink to it.
    #
    # :files is a Hash of name => contents that should be written to the
    # repository. If `contents` is nil, the named file will be deleted.
    # This is usually used to write "info/nwo".
    #
    # :initial_branch is an optional String specifying the name for the initial
    # branch in the newly created repository. If nil, falls back to the
    # configured git default initial branch name.
    #
    # Returns nothing.
    rpc_writer :ensure_initialized, no_git_repo: true
    def ensure_initialized(hooks_template: nil, files: {}, initial_branch: nil)
      init(initial_branch:)

      if hooks_template
        raise SystemError, "Can't make hooks a link to '#{hooks_template}' because it does not exist!" unless Dir.exist?(hooks_template)
        hooks = File.join(path, "hooks")
        FileUtils.rm_rf hooks
        File.symlink hooks_template, File.join(path, "hooks")
      end

      files.each do |file, value|
        if value
          fs_write file, value
        else
          fs_delete file
        end
      end

      nil
    end

    # Public: Remove repository from disk.
    rpc_writer :remove, no_git_repo: true
    def remove
      FileUtils.rm_rf(path) if exist?
      nil
    end

    # Public: Check that the repository exists on disk and is initialized.
    #
    # Returns true when repository exists and is initialized, false otherwise.
    rpc_reader :exist?, no_git_repo: true
    def exist?
      !!File.exist?("#{path}/config")
    end

    # Public: Ensure that a directory exists, creating it if necessary.
    #
    # Returns nil or raises GitRPC::CommandFailed.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    rpc_writer :ensure_dir, no_git_repo: true
    def ensure_dir(dir)
      dir = pathname(dir)

      # Don't use FileUtils.mkdir_p for this.  It doesn't report errors nicely.
      res = spawn(["mkdir", "-p", dir])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end

    # Public: Read contents of of a file from a given position.
    #
    # Returns the string file contents.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    rpc_reader :fs_read
    def fs_read(file, position = 0)
      repository_required
      pathname = pathname(file)
      File.open(pathname, "rb") do |f|
        f.seek(position)
        f.read
      end
    rescue ::SystemCallError => boom
      raise GitRPC::SystemError, boom
    end

    # Internal: Read the nwo file from this repo
    #
    # Returns nil if the file or repo don't exist.
    # Returns the name with owner of this repository.
    def nwo
      return @nwo if defined?(@nwo)
      @nwo = fs_read("info/nwo").chomp
    rescue GitRPC::SystemError, GitRPC::InvalidRepository
      @nwo = nil
    end

    # Public: Write to a new file, moving into place atomically.
    #
    # file - File relative to the root of the repository.
    # data - Contents of the file or nil to create file but not write to it.
    #
    # Returns nothing.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    #
    # XXX The temp file should probably be written into GIT_DIR/tmp/* to avoid
    #     writing into directories that scan files (refs, reflogs, etc).
    rpc_writer :fs_write
    def fs_write(file, data = nil)
      repository_required
      pathname = pathname(file)
      dirname, basename = File.dirname(pathname), File.basename(pathname)
      FileUtils.mkdir_p(dirname)

      tmp_path = "#{dirname}/.#{basename}-#$$-#{(Time.now.to_f * 100000).to_i}"
      File.open(tmp_path, "wb") { |f| f.write(data) if data }
      File.rename(tmp_path, pathname)

      nil
    rescue ::SystemCallError => boom
      raise GitRPC::SystemError, boom
    ensure
      (File.unlink(tmp_path) rescue nil) if tmp_path
    end

    # Public: Create a lock file only if no one else is holding or
    # obtaining it.  Locks older than a max age are considered stale and
    # will be granted to someone else, possibly us.  If we get the file,
    # we fill it with some contents, though not atomically.
    #
    # file - File relative to the root of the repository.
    # contents - Contents of the file to create
    # max_age - How old a lock file must be, in seconds, to be considered
    #           stale
    #
    # Returns true if we got the lock, false otherwise.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    rpc_writer :fs_lock
    def fs_lock(file, contents, max_age)
      repository_required
      pathname = pathname(file)
      loop do
        begin
          fp = File.new(pathname, File::WRONLY|File::CREAT|File::EXCL)
          fp.write(contents)
          fp.close
          return true
        rescue Errno::EEXIST
          # lock exists.  is it fresh?
          now = Time.now
          begin
            return false if now - File.stat(pathname).mtime <= max_age
          rescue Errno::ENOENT
            continue  # lock holder just deleted it; try CREAT|EXCL again
          end

          fp = File.open(pathname, File::WRONLY|File::CREAT)
          # it was stale, but someone else is currently refreshing it.
          return false unless fp.flock(File::LOCK_EX|File::LOCK_NB)
          # we're up to refresh it; make sure it wasn't already refreshed by
          # someone else.
          if now - fp.stat.mtime <= max_age
            fp.flock(File::LOCK_UN)
            fp.close
            return false
          end

          # if we get this far, we are the ones refreshing it.
          FileUtils.touch(pathname, :mtime => Time.now)
          fp.flock(File::LOCK_UN)
          fp.write(contents)
          fp.flush
          fp.truncate(fp.pos)
          fp.close
          return true
        end
      end
    end

    # Public: Move a file or directory in the repository on disk.
    #
    # from_file - Current file relative to the root of the repository.
    # to_file   - New file name relative to the root of the repository.
    #
    # Returns nothing.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    rpc_writer :fs_move, no_git_repo: true
    def fs_move(from_file, to_file)
      from_path = pathname(from_file)
      to_path = pathname(to_file)
      dirname = File.dirname(to_path)
      FileUtils.mkdir_p(dirname)

      File.rename(from_path, to_path)
      nil
    rescue ::SystemCallError => boom
      raise GitRPC::SystemError, boom
    end

    # Public: Remove a file or directory from the repository on disk.
    #
    # file - File relative to the root of the repository.
    #
    # Returns nothing.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    rpc_writer :fs_delete
    def fs_delete(file)
      repository_required
      pathname = pathname(file)
      FileUtils.rm_rf(pathname)
      nil
    rescue ::SystemCallError => boom
      raise GitRPC::SystemError, boom
    end

    # Public: Check if a specific file exists within the repository.
    #
    # file  - File relative to the root of the repository.
    # mtime - Optional new modified time of the file as an int number of seconds
    #         since epoch.
    #
    # Returns the integer mtime timestamp.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    # Raises GitRPC::InvalidRepository when the repository does not exist.
    rpc_reader :fs_exist?
    def fs_exist?(file)
      repository_required
      pathname = pathname(file)
      !!File.exist?(pathname)
    rescue ::SystemCallError => boom
      raise GitRPC::SystemError, boom
    end

    # Public: Get the size of the file, in bytes.
    #
    # file - String file to stat relative to the git repository directory.
    #
    # Returns the size in bytes.
    rpc_reader :fs_size
    def fs_size(file)
      repository_required
      pathname = pathname(file)
      File.size(pathname)
    rescue ::SystemCallError => boom
      raise GitRPC::SystemError, boom
    end

    # Public: Truncate a file to a given length, in bytes.
    #
    # file - String file to truncate relative to the git repository
    # directory.
    # size - The desired new size of the file.  This function will
    #        increase the size of the file, if the size argument is
    #        greater than the file's current size.
    rpc_writer :fs_truncate
    def fs_truncate(file, size)
      repository_required
      pathname = pathname(file)
      File.truncate(pathname, size)
    rescue ::SystemCallError => boom
      raise GitRPC::SystemError, boom
    end

    # Create the network parent directory containing the given repo, wiki,
    # or network, if it doesn't already exist.
    rpc_writer :create_network_dir, no_git_repo: true
    def create_network_dir
      raise GitRPC::Error, "path is nil" unless path
      network_dir = path.sub(%r{/(network|\d+(\.wiki)?).git/?$}, "")
      FileUtils.mkdir_p(network_dir)
      nil
    end

    # Push copies of a repo or network to one or more targets.
    #
    # urls - an array of destinations.  Each destination can be anything
    #        rsync can deal with, e.g., an absolute path on the local
    #        filesystem, or a host:/path pair.
    #
    # push_to is an rpc_reader because it runs on any (single) source node
    # and fans out to all destinations.  If this were an rpc_writer, each
    # possible source would copy to each destination, which would be racey
    # and redundant.
    rpc_reader :push_to
    def push_to(urls)
      src = path.chomp("/")
      # TODO: parallelize these calls by spawning three rsyncs in the
      # background and waiting for them to finish.
      urls.each do |dest|
        res = spawn(["rsync", "-av", "--stats", src, dest])
        raise CommandFailed.new(res) unless res["ok"]
        res = spawn(["rsync", "-av", "--delete", "--exclude=/*/gitmon.model", "--stats", src, dest])
        raise CommandFailed.new(res) unless res["ok"]
        if res["out"] !~ /^Number of (regular )?files transferred: 0$/
          raise GitRPC::VerificationFailed.new(res.to_s, urls.to_s, "#{src} changed after transfer to #{dest}")
        end
      end
    end

    # Return a list of all children that contain a file with the given
    # name.
    #
    # file - a filename likely to appear in repo or wiki directories
    #
    # Returns an array of the subdirectories that contain that file.
    rpc_reader :forks_with_file
    def forks_with_file(file)
      Dir.chdir(path) do
        Dir["*"].select { |child| File.exist?("#{child}/#{file}") }
      end
    end

    # Public: Get disk free space
    #
    # paths - an array of paths, or nil to get free space on all mountpoints.
    #
    # Returns a [free_space_mb, total_space_mb] array.
    # Raises GitRPC::CommandFailed on failure.
    rpc_reader :disk_free_space, no_git_repo: true
    def disk_free_space
      GitRPC.repository_root ||= GitHub.repository_root # for tests
      res = spawn(["df", "-m", "--", GitRPC.repository_root])
      raise GitRPC::CommandFailed.new(res) if !res["ok"]

      line = res["out"].split("\n")[1]
      tok = line.split
      free_space_mb = tok[3].to_i
      total_space_mb = tok[2].to_i + free_space_mb
      [free_space_mb, total_space_mb]
    end

    # Internal: Return the full path to a file relative to the current git
    # directory. This provides some protection from accessing files outside
    # the repository root.
    #
    # Returns a full path string.
    # Raises GitRPC::IllegalPath when an attempt is made to access a path
    # outside of the git repository.
    def pathname(file)
      full_path = File.expand_path(file, path)
      if full_path[0, path.size] != path
        raise IllegalPath, file
      end
      full_path
    end

    # Internal: Ensure that the repository exists.
    #
    # Raises GitRPC::InvalidRepository when the repository does not exist.
    def repository_required
      return if exist?
      raise GitRPC::InvalidRepository, "Does not exist: #{path}"
    end

    def local_host_name_short
      local_host_name.split(".", 2).first
    end
    private :local_host_name_short

    def local_host_name
      @local_host_name ||= Socket.gethostname
    end
    private :local_host_name
  end

  # Raised when the transfer succeeded but the verification step showed that
  # not all objects were transferred. One or more repositories are actively
  # receiving data when this happens.
  class VerificationFailed < Error
    attr_reader :spawn_result, :urls
    def failbot_context
      { :spawn_result => @spawn_result, :urls => @urls }
    end

    def initialize(spawn_result, urls, msg)
      @spawn_result, @urls = spawn_result, urls
      super(msg)
    end
  end
end
