# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: rsync
    #
    # src        - source directory or remote url
    # dest       - destination directory (must be within the rpc object's path)
    # archive    - archive mode
    # recursive  - recurse into directories
    # verbose    - increase verbosity
    # hard_links - preserve hard links
    # delete     - delete extraneous files from dest dirs
    # checksum   - skip based on checksum, not mod-time & size
    # append     - append data onto shorter files
    # stats      - give some file-transfer stats
    # include    - array of files to include
    # exclude    - array of files to exclude
    #
    # Returns a hash with "ok", "out", "err", and "status" elements.
    def rsync(src, dest, options = {})
      send_message(:rsync, src, dest, **options)
    end
  end
end
