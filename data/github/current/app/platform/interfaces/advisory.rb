# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Advisory
      include Platform::Interfaces::Base

      visibility :under_development

      description "A security advisory published either by GitHub or repository maintainers"

      global_id_field :id, description: "The Node ID of the Advisory object"

      field :ghsa_id, String, "The GitHub Security Advisory ID", null: false
      field :summary, String, "A short plaintext summary of the advisory", null: false
      field :description, String, "A plaintext description of the advisory", null: false
      field :severity, Enums::SecurityAdvisorySeverity, "The severity of the advisory", null: false
      field :permalink, Scalars::URI, "The permalink for the advisory", null: true
      field :published_at, Scalars::DateTime, "When the advisory was published", null: false

      definition_methods do
        def resolve_type(object, context)
          Objects::InternalRepositoryAdvisory
        end
      end
    end
  end
end
