module API
  module Enums
    class ContentEncoding < Types::BaseEnum
      description "Content encodings"

      value("PLAIN")
      value("BASE_64")
    end

    def ContentEncoding.decode(encoded:, encoding:)
      case encoding
      when "PLAIN"
        encoded
      when "BASE_64"
        Base64.decode64(encoded)
      else
        raise TypeError
      end
    end
  end
end
