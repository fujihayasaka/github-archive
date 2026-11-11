# typed: strict
# frozen_string_literal: true

module Exporter
  # Service to provide ActiveRecord scopes for different model types during archiving.
  #
  # This service abstracts scope logic for archivers, providing the necessary preloads
  # for efficient batch archiving. Unlike SerializerScope, this doesn't merge with a base
  # scope since BaseArchiver doesn't define one.
  #
  # Only models with archiving needs are defined here (attachment, release, repository).
  #
  # Usage:
  #   scope_service = Exporter::ArchiverScope.new(model_type: "attachment")
  #   scope = scope_service.scope
  #   attachments = Attachment.where(id: ids).merge(scope).to_a
  class ArchiverScope
    sig { params(model_type: String).void }
    def initialize(model_type:)
      @model_type = model_type
    end

    # Returns the scope for archiving, with necessary preloads.
    # Returns {} if no custom preloads are needed for this model type.
    sig { returns(T.any(ActiveRecord::Relation, T::Hash[T.untyped, T.untyped])) }
    def scope
      custom_preloads
    end

    private

    sig { returns(String) }
    attr_reader :model_type

    # Returns custom preloads for models that need them for archiving.
    # Returns {} if no custom preloads are needed for this model type.
    sig { returns(T.any(ActiveRecord::Relation, T::Hash[T.untyped, T.untyped])) }
    def custom_preloads
      case model_type
      when "attachment"
        Attachment.preload(:asset)
      when "release"
        Release.preload(:release_assets)
      when "repository"
        Repository.preload(:owner)
      else
        # No custom preloads for other model types
        {}
      end
    end
  end
end
