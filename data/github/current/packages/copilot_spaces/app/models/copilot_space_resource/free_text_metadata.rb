# typed: true
# frozen_string_literal: true

class CopilotSpaceResource::FreeTextMetadata < CopilotSpaceResource::Metadata
  attr_reader :text, :name

  sig { override.params(json: T.untyped).returns(T.attached_class) }
  def self.from_json(json)
    new(
      text: json["text"],
      name: json["name"]
    )
  end

  def initialize(text:, name:)
    @text = text
    @name = name
  end

  sig do
    override
      .params(opts: T::Hash[Symbol, T.untyped])
      .returns(T.nilable(MonolithTwirp::Copilotapi::CustomCopilots::V1::FreeTextMetadata))
  end
  def to_copilot_config_twirp(opts: {})
    MonolithTwirp::Copilotapi::CustomCopilots::V1::FreeTextMetadata.new(contents: text, name: name)
  end
end
