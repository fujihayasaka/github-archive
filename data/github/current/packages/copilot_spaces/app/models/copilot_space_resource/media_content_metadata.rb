# typed: true
# frozen_string_literal: true

class CopilotSpaceResource::MediaContentMetadata < CopilotSpaceResource::Metadata
  attr_reader :media_type, :name, :url, :height, :width

  sig { override.params(json: T.untyped).returns(T.attached_class) }
  def self.from_json(json)
    new(
      name: json["name"],
      url: json["url"],
      media_type: json["media_type"],
      height: json["height"],
      width: json["width"],
    )
  end

  sig { params(name: String, url: String, media_type: String, height: T.nilable(Integer), width: T.nilable(Integer)).void }
  def initialize(name:, url:, media_type:, height:, width:)
    @name = name
    @media_type = media_type
    @height = height
    @width = width
    @url = url
  end

  sig do
    override
      .params(opts: T::Hash[Symbol, T.untyped])
      .returns(T.nilable(MonolithTwirp::Copilotapi::CustomCopilots::V1::MediaContentMetadata))
  end
  def to_copilot_config_twirp(opts: {})
    MonolithTwirp::Copilotapi::CustomCopilots::V1::MediaContentMetadata.new(
      name: name,
      url: url,
      media_type: media_type,
      height: height,
      width: width,
    )
  end
end
