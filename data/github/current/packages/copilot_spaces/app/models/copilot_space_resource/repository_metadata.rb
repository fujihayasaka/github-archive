# typed: true
# frozen_string_literal: true

class CopilotSpaceResource::RepositoryMetadata < CopilotSpaceResource::Metadata
  include GitHub::Memoizer

  attr_reader :repository_id

  sig { override.params(json: T.untyped).returns(T.attached_class) }
  def self.from_json(json)
    new(
      repository_id: json["repository_id"],
    )
  end

  def initialize(repository_id:)
    @repository_id = repository_id
  end

  memoize def repository
    if repository_id.present?
      Repositories::Public.find_active(repository_id)
    end
  end

  sig do
    override
      .params(opts: T::Hash[Symbol, T.untyped])
      .returns(T.nilable(MonolithTwirp::Copilotapi::CustomCopilots::V1::RepositoryMetadata))
  end
  def to_copilot_config_twirp(opts: {})
    return unless repository

    MonolithTwirp::Copilotapi::CustomCopilots::V1::RepositoryMetadata.new(name_with_owner: repository.name_with_display_owner)
  end
end
