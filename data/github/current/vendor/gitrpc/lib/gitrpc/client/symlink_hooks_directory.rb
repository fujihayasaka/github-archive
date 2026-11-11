# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    # Public: symlink hooks directory
    #
    # link_source - directory to link to
    #
    # Returns true.
    def symlink_hooks_directory(options = {})
      send_message(:symlink_hooks_directory, **options)
    end
  end
end
