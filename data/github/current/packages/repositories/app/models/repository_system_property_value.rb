# typed: strict
# frozen_string_literal: true

class RepositorySystemPropertyValue < ApplicationRecord::Domain::Repositories
  # target_class_name needs to be defined prior to including CustomPropertiesCore::SystemProperties::ValueBase
  #
  # This is the class name of the model that these values target, or that the value is defined for.
  # This is used to define the active record association between the value and its target.
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see Repository
  # @see CustomPropertiesCore::SystemProperties::ValueBase
  sig { returns(String) }
  def self.target_class_name
    T.must(Repository.name)
  end

  enum :definition_id, {
    deployable: 0,
    deployed: 1,
    "runtime-risk": 2,
  }, suffix: true

  # Generates the event payload for system property value events.
  sig { params(target: T.nilable(Repository)).returns(T::Hash[Symbol, T.untyped]) }
  def self.event_payload_extension(target)
    {
      repo: target,
      org: target&.owner,
    }
  end

  include CustomPropertiesCore::SystemProperties::ValueBase
end
