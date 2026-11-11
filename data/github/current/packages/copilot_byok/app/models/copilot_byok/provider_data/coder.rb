# typed: true
# frozen_string_literal: true

module CopilotByok
  module ProviderData
    # ActiveRecord serializer coder
    class Coder
      # Serialize object to Base64 encoded MessagePack for database storage
      sig do
        params(
          obj: T.any(CustomModel::AwsBedrock, CustomKey::OpenAICompatible, CustomKey::AwsBedrock)
        ).returns(T.nilable(String))
      end
      def self.dump(obj)
        return nil if obj.nil?

        Base64.strict_encode64(FACTORY.pack(obj))
      end

      # Deserialize from Base64 encoded MessagePack or legacy format
      sig do
        params(data: T.nilable(String)).returns(
          T.nilable(T.any(CustomKey::OpenAICompatible, CustomModel::AwsBedrock, CustomKey::AwsBedrock))
        )
      end
      def self.load(data)
        return nil if data.nil?

        begin
          decoded_data = Base64.strict_decode64(data)
          FACTORY.unpack(decoded_data)
        rescue MessagePack::MalformedFormatError, ArgumentError
          nil
        end
      end
    end
  end
end
