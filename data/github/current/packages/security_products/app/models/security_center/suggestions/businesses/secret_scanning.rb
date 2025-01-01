# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Businesses
      class SecretScanning < Base

        class FilterType < T::Enum
          enums do
            SecretType = new
            Provider = new
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
          return [] unless type == FilterType::SecretType || type == FilterType::Provider

          filter = ::SecretScanningControllerHelper::GroupByAggregation::TOKEN_TYPE if type == FilterType::SecretType
          filter = ::SecretScanningControllerHelper::GroupByAggregation::TOKEN_PROVIDER if type == FilterType::Provider

          filter_options, error = alert_query_service.get_filter_options(filter:)
          return [] if error

          suggestions = T.let([], T::Array[Suggestion])
          filter_options.each do |group|
            group[:items].each do |item|
              item_label = item[:label]
              item_slug = item[:slug]

              item_slug_downcase = item_slug.downcase
              next if selected_values.present? && selected_values.map(&:downcase).include?(item_slug_downcase)
              next if value.present? && item_slug_downcase.exclude?(value.downcase)

              suggestions << Suggestion.new(label: item_label, value: item_slug, description: item_slug)
            end
          end

          suggestions.take(limit)
        end

        private

        sig { returns(::SecretScanning::AlertQueryService) }
        memoize def alert_query_service
          ::SecretScanning::AlertQueryService.for_business(
            business:,
            organizations: authorized_orgs,
            current_user: user,
            user_session: user_session
          )
        end
      end
    end
  end
end
