# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Businesses
      class Dependabot < Base

        class FilterType < T::Enum
          enums do
            Ecosystem = new
            Package = new
          end
        end

        sig { returns(::Business) }; attr_reader :business
        sig { returns(::User) }; attr_reader :user
        sig { returns(::UserSession) }; attr_reader :user_session
        sig { returns(FilterType) }; attr_reader :type
        sig { returns(T::Array[Organization]) }; attr_reader :authorized_orgs

        sig do
          params(
            business: ::Business,
            user: ::User,
            user_session: ::UserSession,
            type: FilterType,
            authorized_orgs: T::Array[Organization],
            kwargs: T.untyped
          ).void
        end
        def initialize(business:, user:, user_session:, type:, authorized_orgs:, **kwargs)
          super(**T.unsafe(kwargs))
          @business = business
          @user = user
          @user_session = user_session
          @type = type
          @authorized_orgs = authorized_orgs
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if authorized_orgs.empty?
          return [] unless type == FilterType::Ecosystem || type == FilterType::Package

          filter_options = case type
          when FilterType::Ecosystem
            alert_query.ecosystem_filter_options.compact
          when FilterType::Package
            alert_query.package_filter_options.compact
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
            business:,
            organization_ids: authorized_orgs.map { |org| org.id },
            user:,
            user_session:
          )
        end
      end
    end
  end
end
