# typed: true
# frozen_string_literal: true

class CopilotSpaceResource::UploadedTextFileMetadata < CopilotSpaceResource::Metadata
  attr_reader :name

  private_class_method :new

  sig { override.params(json: T.untyped).returns(T.attached_class) }
  def self.from_json(json)
    new(name: json["name"])
  end

  sig { params(name: String).void }
  def initialize(name:)
    @name = name
  end

  sig do
    override
      .params(opts: T::Hash[Symbol, T.untyped])
      .returns(T.nilable(MonolithTwirp::Copilotapi::CustomCopilots::V1::UploadedTextFileMetadata))
  end
  def to_copilot_config_twirp(opts: {})
    MonolithTwirp::Copilotapi::CustomCopilots::V1::UploadedTextFileMetadata.new(name:)
  end
end
