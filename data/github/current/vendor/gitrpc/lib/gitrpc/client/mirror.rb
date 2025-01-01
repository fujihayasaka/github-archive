# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    # Public: fetches the commits indicated by from_prefix in the remote repo and stores them
    #   under to_prefix in the local repo.
    #
    # url - the url of the remote repository
    # refspecs - either a) a String prefix of the refs which we will be mirroring
    #                or b) an Array of refspecs which be reconstituted under the to_prefix
    # to_prefix - the ref prefix under which selected refs will be placed. Terminated with '/'.
    # mirror_env - the git ENV for the mirror command
    #
    # NOTE: when the refspec is a String, it is expected to be terminated with a '/'. It is not
    #   appended to the to_prefix like the target of each one is when it is an array.
    def fetch_for_mirror(url, refspecs, to_prefix, mirror_env)
      send_message(:fetch_for_mirror, url, refspecs, to_prefix, mirror_env)
    end

    def delete_mirror_temp_refs(mirror_prefix, cutoff, mirror_env)
      send_message(:delete_mirror_temp_refs, mirror_prefix, cutoff, mirror_env)
    end
  end
end
