# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Orgs
      class Team < Base
        extend T::Sig

        sig { returns(Organization) }; attr_reader :organization
        sig { returns(User) }; attr_reader :user
        sig { returns(T::Boolean) }; attr_reader :skip_limit

        sig { params(organization: Organization, user: User, skip_limit: T::Boolean, kwargs: T.untyped).void }
        def initialize(organization:, user:, skip_limit: false, **kwargs)
          super(**T.unsafe(kwargs))
          @organization = organization
          @user = user

          # The Teams multi-select dropdown does not re-fetch new results as the user scrolls or filters.
          # Therefore, all Teams must be fetched.
          @skip_limit = skip_limit
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          teams_rel = organization
            .visible_teams_for(user, fields: [:name, :organization_id, :slug])
            .order(:name)

          teams_rel = teams_rel.limit(limit) unless @skip_limit
          teams_rel = teams_rel.where.not(slug: selected_values) if selected_values.present?
          teams_rel = teams_rel.where("slug LIKE ?", "%#{value}%") if value.present?

          teams_rel.map { |team| Suggestion.new(label: team.name, value: team.slug, description: team.slug) }
        end
      end
    end
  end
end
