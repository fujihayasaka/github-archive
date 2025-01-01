# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Orgs
      class Dependabot < Base

        class FilterType < T::Enum
          enums do
            Ecosystem = new
            Package = new
            ArtifactRegistryURL = new
          end
        end

        sig { returns(::Organization) }; attr_reader :organization
        sig { returns(::User) }; attr_reader :user
        sig { returns(::UserSession) }; attr_reader :user_session
        sig { returns(FilterType) }; attr_reader :type
        sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :allowed_repo_ids

        sig do
          params(
            organization: ::Organization,
            user: ::User,
            user_session: ::UserSession,
            type: FilterType,
            allowed_repo_ids: T.nilable(T::Array[Integer]),
            kwargs: T.untyped
          ).void
        end
        def initialize(organization:, user:, user_session:, type:, allowed_repo_ids:, **kwargs)
          super(**T.unsafe(kwargs))
          @organization = organization
          @user = user
          @user_session = user_session
          @type = type
          @allowed_repo_ids = allowed_repo_ids
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if allowed_repo_ids&.empty?
          return [] unless type == FilterType::Ecosystem || type == FilterType::Package || type == FilterType::ArtifactRegistryURL

          filter_options = case type
          when FilterType::Ecosystem
            alert_query.ecosystem_filter_options.compact
          when FilterType::Package
            alert_query.package_filter_options.compact
          when FilterType::ArtifactRegistryURL
            alert_query.artifact_registry_url_filter_options.compact
          end

          suggestions = T.let([], T::Array[Suggestion])
          filter_options.each do |item|
            item_label = item[:label]
            item_slug = item[:slug]

            item_slug_downcase = item_slug.downcase
            next if selected_values.present? && selected_values.map(&:downcase).include?(item_slug_downcase)
            next if value.present? && item_slug_downcase.exclude?(value.downcase)

            suggestions << Suggestion.new(label: item_label, value: item_slug)
          end

          suggestions.take(limit)
        end

        private

        sig { returns(::RepositoryVulnerabilityAlert::UngroupedAlertQuery) }
        memoize def alert_query
          ::RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(
            organization:,
            user:,
            user_session:,
            allowed_repository_ids: allowed_repo_ids
          )
        end
      end
    end
  end
end
