# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Orgs
      class Repo < Base
        extend T::Sig

        sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :allowed_repo_ids
        sig { returns(Integer) }; attr_reader :owner_id

        sig { params(allowed_repo_ids: T.nilable(T::Array[Integer]), owner_id: Integer, kwargs: T.untyped).void }
        def initialize(allowed_repo_ids:, owner_id:, **kwargs)
          super(**T.unsafe(kwargs))
          @allowed_repo_ids = allowed_repo_ids
          @owner_id = owner_id
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if allowed_repo_ids&.empty?

          rel = RepositorySecurityCenterConfig
            .where(owner_id: owner_id)
            .then do |rel|
              next rel if allowed_repo_ids.nil? # admin

              rel.where(repository_id: allowed_repo_ids) # non-admin
            end
            .order(:name)
            .limit(limit)

          rel = rel.where.not(name: selected_values) if selected_values.present?
          rel = rel.where("name LIKE ?", "%#{value}%") if value.present?

          rel.pluck(:name).map { |name| Suggestion.new(value: name) }
        end
      end
    end
  end
end
