# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    class RepositoryMetadataComponent < ApplicationComponent

      TEST_SELECTOR = "security-center-coverage-repository-metadata"
      NAME_TEST_SELECTOR = "security-center-coverage-repository-metadata-name"
      UPDATED_AT_TEST_SELECTOR = "security-center-coverage-repository-metadata-updated-at"

      class Data < T::Struct

        const :id, Integer
        const :name, String
        const :href, String
        const :visibility, String
        const :visibility_href, String
        const :archived, T::Boolean
        const :ghas_enabled, T::Boolean
        const :is_advisory_workspace, T::Boolean, default: false
        const :updated_at, T.nilable(T.any(Time, ActiveSupport::TimeWithZone))
        const :repo_locked, T::Boolean, default: false

        sig { params(id: Integer, name: String, href: String, visibility: String, visibility_href: String, archived: T::Boolean, ghas_enabled: T::Boolean, is_advisory_workspace: T::Boolean, updated_at: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)), repo_locked: T::Boolean).void }
        def initialize(id:, name:, href:, visibility:, visibility_href:, archived:, ghas_enabled:, is_advisory_workspace: false, updated_at: nil, repo_locked: false)
          raise ArgumentError, "visibility must be one of: #{Repository::VISIBILITIES}" unless Repository::VISIBILITIES.include? visibility.downcase
          super
        end
      end

      sig { params(data: Data).void }
      def initialize(data)
        @id = T.let(data.id, Integer)
        @name = T.let(data.name, String)
        @href = T.let(data.href, String)
        @visibility_label = T.let("#{data.visibility} #{"archive" if data.archived}".strip.humanize, String)
        @visibility_href = T.let(data.visibility_href, String)
        @ghas_enabled = T.let(data.ghas_enabled, T::Boolean)
        @updated_at = T.let(data.updated_at, T.nilable(Object))
        @is_advisory_workspace = T.let(data.is_advisory_workspace, T::Boolean)
        @repo_locked = T.let(data.repo_locked, T::Boolean)
      end
    end
  end
end
