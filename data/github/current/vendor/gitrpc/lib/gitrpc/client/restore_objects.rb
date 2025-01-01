# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Restore missing/corrupt objects in a repository
    #
    # max   - Set the max number of objects to be restored at once.
    #
    # Returns the result of the command.
    def restore_objects(options = {})
      send_message(:restore_objects, **options)
    end
  end
end
