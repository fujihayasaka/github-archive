# typed: true
# frozen_string_literal: true

class Platform::Models::MigrationMapConflict
  attr_reader :model_type, :source_url, :target_url, :recommended_action, :notes

  def initialize(model_type, source_url, target_url, recommended_action, notes)
    @model_type = model_type
    @source_url = source_url
    @target_url = target_url
    @recommended_action = recommended_action
    @notes = notes.to_s
  end

  PACKER = lambda do |obj|
    GitHub::Cache::Codec.factory.pack({
      model_type: obj.model_type,
      source_url: obj.source_url,
      target_url: obj.target_url,
      recommended_action: obj.recommended_action,
      notes: obj.notes
    })
  end

  UNPACKER = lambda do |data|
    hash = GitHub::Cache::Codec.factory.unpack(data)
    Platform::Models::MigrationMapConflict.new(
      hash[:model_type],
      hash[:source_url],
      hash[:target_url],
      hash[:recommended_action],
      hash[:notes]
    )
  end

  GitHub::Cache::Codec.register_type(
    GitHub::Cache::Codec::MIGRATION_MAP_CONFLICT_TYPE,
    self)
end
