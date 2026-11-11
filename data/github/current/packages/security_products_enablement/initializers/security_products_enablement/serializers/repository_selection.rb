# typed: strict
# frozen_string_literal: true

class SecurityProductsEnablementRepositorySelectionSerializer < ActiveJob::Serializers::ObjectSerializer
  sig { params(repositories: SecurityProductsEnablement::RepositorySelection).returns(T::Hash[String, T.untyped]) }
  def serialize(repositories)
    super(
      "value" => repositories.value.serialize,
      "repository_ids" => repositories.selected_repository_ids
    )
  end

  sig { params(hash: T::Hash[String, T.untyped]).returns(SecurityProductsEnablement::RepositorySelection) }
  def deserialize(hash)
    value_str = hash["value"]
    repository_ids = hash["repository_ids"] || []

    value = SecurityProductsEnablement::RepositorySelection::Value.deserialize(value_str)
    SecurityProductsEnablement::RepositorySelection.new(value, repository_ids)
  end

  sig { returns(T.class_of(SecurityProductsEnablement::RepositorySelection)) }
  def klass
    SecurityProductsEnablement::RepositorySelection
  end
end

Rails.application.config.active_job.custom_serializers << SecurityProductsEnablementRepositorySelectionSerializer
