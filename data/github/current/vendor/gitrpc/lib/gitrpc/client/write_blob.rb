# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Write a blob into the repository
    def write_blob(content)
      send_message(:write_blob, content)
    end
  end
end
