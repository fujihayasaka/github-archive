# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Orgs
      class Topic < Base

        sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :allowed_repo_ids

        sig { params(organization: Organization, allowed_repo_ids: T.nilable(T::Array[Integer]), kwargs: T.untyped).void }
        def initialize(organization:, allowed_repo_ids: nil, **kwargs)
          super(**T.unsafe(kwargs))
          @organization = organization
          @allowed_repo_ids = allowed_repo_ids
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if allowed_repo_ids&.empty?
          return [] if topic_ids.blank?

          ::Topic
            .select(:name, :short_description)
            .where(id: topic_ids)
            .then do |rel|
              next rel unless selected_values.present?
              rel.where.not(name: selected_values)
            end
            .then do |rel|
              next rel unless value.present?
              rel.where("name LIKE ?", "%#{value}%")
            end
            .then do |rel|
              next rel.order(:name) unless value.present?
              # This puts exact matches first, then sorts by name ASC
              # e.g. ORDER BY `topics`.`name` = $value DESC, `topics`.`name` ASC
              exact_match = ::Topic.arel_table[:name].eq(value)
              rel.order(Arel::Nodes::Descending.new(exact_match)).order(:name)
            end
            .limit(limit)
            .map do |topic|
              Suggestion.new(
                description: topic.short_description,
                value: topic.name
              )
            end
        end

        private

        sig { returns(T::Array[Integer]) }
        memoize def topic_ids
          ::RepositoryTopic
            .then do |rel|
              if allowed_repo_ids.nil?
                rel
                  .joins(:repository)
                  .where(repository: { owner: @organization })
                  .limit(1_000)
              else
                rel.applied_to(repository_ids: allowed_repo_ids, limit: 1_000) # non-admin
              end
            end
            .select(:topic_id)
            .distinct
            .pluck(:topic_id)
        end
      end
    end
  end
end
