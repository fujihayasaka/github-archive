# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

# Client implementations of disk related repository access. The client side
# of these methods typically just pass directly through to the backend since
# caching is rare.
module GitRPC
  class Client
    # Public: Create and initialize the repository on disk. The repository is
    # guaranteed to be in a good state when this call returns. Repositories are
    # always created with the bare option set true.
    #
    # This method is idempotent and non-destructive. Calling init on an already
    # initialized repository has no effect.
    #
    # Returns nil.
    # Raises GitRPC::Failure when the repository can not be created.
    def init
      send_message(:init)
    end

    def ensure_initialized(options)
      send_message(:ensure_initialized, **options)
    end

    # Public: Remove the repository from disk.
    #
    # Returns nil.
    def remove
      send_message(:remove)
    end

    # Public: Check that the repository exists on disk and is valid. The
    # directory must exist and the config file must be present. Otherwise the
    # repository is not a valid target for git operations and should be
    # considered non-existent.
    #
    # Returns true when the repository is a valid target for git operations.
    def exist?
      send_message(:exist?)
    end

    # Public: Check that the repository exists on all replicas.
    #
    # Returns a map of {"host1" => true, "host2" => false}
    def all_replicas_exist?
      if backend.disagreement_possible?
        send_demux(:exist?)
      else
        { backend.url.host => exist? }
      end
    end

    # Public: Ensure that a directory exists, creating it if necessary.
    #
    # Returns nil or raises GitRPC::CommandFailed.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    def ensure_dir(dir)
      send_message(:ensure_dir, dir)
    end

    # Public: Read entire contents of file within the repository directory. This
    # does not operate on git data but on the raw repository structure.
    #
    # file - Relative path to file to read.
    # position - Optional: a number of bytes to skip reading from the beginning of the file.
    #
    # Returns the file content as a string.
    # Raises GitRPC::SystemError if the file doesn't exist or another system
    # error occurs.
    def fs_read(file, position = 0)
      send_message(:fs_read, file, position)
    end

    def async_fs_read(file, position = 0)
      async_send_message(:fs_read, file, position)
    end

    # Public: Write entire contents of file. This does not operate on git data
    # but on the raw repository structure.
    #
    # file - Relative path to the file to write.
    # data - String data to write to the file.
    #
    # Returns nothing.
    # Raises GitRPC::SystemError if the file doesn't exist or another system
    # error occurs.
    def fs_write(file, data = nil)
      send_message(:fs_write, file, data)
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
    # Raises GitRPC::SystemError if the file could not be created for
    # reasons other than someone else holding it.
    def fs_lock(file, contents, max_age = 3600)
      send_message(:fs_lock, file, contents, max_age)
    end

    # Public: Unlock a previously held lock file.  This just deletes it.  Bad
    # things will happen if you fs_unlock a lock that isn't yours.  If you
    # think it's stale, just try fs_lock with an appropriate max_age.
    #
    # Returns nothing.
    def fs_unlock(file)
      send_message(:fs_delete, file)
    end

    # Public: Remove a file or directory from the repository on disk.
    #
    # file - File relative to the root of the repository.
    #
    # Returns nothing.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    def fs_delete(file)
      send_message(:fs_delete, file)
    end

    # Public: Move a file or directory in the repository on disk.
    #
    # from_file - Current file relative to the root of the repository.
    # to_file   - New file name relative to the root of the repository.
    #
    # Returns nothing.
    # Raises GitRPC::IllegalPath when accessing file outside of repository.
    def fs_move(from_file, to_file)
      send_message(:fs_move, from_file, to_file)
    end

    # Public: Check that a given file exists in the repository on disk.
    #
    # file - String file to check relative to the git repository directory.
    #
    # Returns true when the when the given file exists inside the repository.
    def fs_exist?(file)
      send_message(:fs_exist?, file)
    end

    # Public: Get the size of the file, in bytes.
    #
    # file - String file to stat relative to the git repository directory.
    #
    # Returns the size in bytes.
    def fs_size(file)
      send_message(:fs_size, file)
    end

    # Public: Truncate a file to a given length, in bytes.
    #
    # file - String file to truncate relative to the git repository directory.
    # size - The desired new size of the file.  This function will
    #        increase the size of the file, if the size argument is
    #        greater than the file's current size.
    def fs_truncate(file, size)
      send_message(:fs_truncate, file, size)
    end

    # Create the network parent directory containing the given repo, wiki,
    # or network, if it doesn't already exist.
    #
    # For example, if the repo is at /c/nw/c4/ca/42/1/1.git, then this
    # function creates /c/nw/c4/ca/42/1.
    def create_network_dir
      send_message(:create_network_dir)
    end

    # Push copies of a repo or network to one or more targets.
    #
    # urls - an array of destinations.  Each destination can be anything
    #        rsync can deal with, e.g., an absolute path on the local
    #        filesystem, or a host:/path pair.
    def push_to(urls)
      send_message(:push_to, urls)
    end

    # Enumerate all forks containing a given file
    def forks_with_file(file)
      send_message(:forks_with_file, file)
    end

    # Public: Get disk free space on the repository root path.
    #
    # Returns a [free_space_mb, total_space_mb] array.
    # Raises GitRPC::CommandFailed on failure.
    def disk_free_space
      send_message(:disk_free_space)
    end
  end
end
