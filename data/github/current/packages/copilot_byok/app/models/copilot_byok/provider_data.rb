# typed: true
# frozen_string_literal: true

module CopilotByok
  module ProviderData
    class Error < StandardError; end

    # Type IDs for MessagePack Provider Data serialization
    OPENAI_COMPATIBLE_CUSTOM_KEY_TYPE_ID = 0x01
    AWS_BEDROCK_CUSTOM_MODEL_TYPE_ID = 0x02
    AWS_BEDROCK_CUSTOM_KEY_TYPE_ID = 0x03
    MICROSOFT_FOUNDRY_CUSTOM_KEY_TYPE_ID = 0x04

    FACTORY = MessagePack::Factory.new

    def self.register_type(type_id, klass)
      packer = ->(obj) { MessagePack.pack(obj.serialize) }
      unpacker = ->(data) {
        h = MessagePack.unpack(data)
        klass.from_hash(h)
      }

      FACTORY.register_type(type_id, klass, packer: packer, unpacker: unpacker)
    end

    register_type(OPENAI_COMPATIBLE_CUSTOM_KEY_TYPE_ID, CustomKey::OpenAICompatible)
    register_type(AWS_BEDROCK_CUSTOM_MODEL_TYPE_ID, CustomModel::AwsBedrock)
    register_type(AWS_BEDROCK_CUSTOM_KEY_TYPE_ID, CustomKey::AwsBedrock)
    register_type(MICROSOFT_FOUNDRY_CUSTOM_KEY_TYPE_ID, CustomKey::MicrosoftFoundry)
  end
end
