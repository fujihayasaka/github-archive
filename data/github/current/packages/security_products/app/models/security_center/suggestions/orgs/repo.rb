# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    module Orgs
      class Repo < Base
        include Scientist

        sig do
          params(
            organization: ::Organization,
            user: ::User,
            user_session: ::UserSession,
            allowed_repo_ids: T.nilable(T::Array[Integer]),
            kwargs: T.untyped,
          ).void
        end
        def initialize(organization:, user:, user_session:, allowed_repo_ids:, **kwargs)
          super(**T.unsafe(kwargs))
          @organization = organization
          @user = user
          @user_session = user_session
          @allowed_repo_ids = allowed_repo_ids
        end

        sig { override.returns(T::Array[Suggestion]) }
        memoize def suggestions
          return [] if @allowed_repo_ids&.empty?

          science "security_center.org_repo_suggestions_ordering" do |e|
            e.use { suggestions_original }
            e.try { suggestions_candidate }
            e.compare do |control, candidate|
              next false unless control.size == candidate.size

              if value.present?
                next true if control.map(&:value) == candidate.map(&:value)

                candidate.first.value == value &&
                  control.first(limit - 1).map(&:value) == candidate.last(limit - 1).map(&:value)
              else
                control.map(&:value) == candidate.map(&:value)
              end
            end
          end
        end

        private

        sig { returns(T::Array[Suggestion]) }
        memoize def suggestions_original
          repos_filterer = SecurityOverviewAnalytics::Dashboards::OrgReposFilterer.new(
            organization: @organization,
            allowed_repo_ids_by_feature: \
              unless @allowed_repo_ids.nil?
                SecurityFeatures.visible_features(@organization).each_with_object({}) do |feature, memo|
                  memo[feature] = @allowed_repo_ids
                end
              end,
            user: @user,
            user_session: @user_session,
            query: ::Search::Queries::SecurityCenter::QueryParser.new(""),
          )

          rel = repos_filterer.any_feature_repo_metadata_rel
            .order(:name)
            .limit(limit)

          rel = rel.where.not(name: selected_values) if selected_values.present?
          rel = rel.where("name LIKE ?", "%#{value}%") if value.present?

          rel.pluck(:name).map { |name| Suggestion.new(value: name) }
        end

        sig { returns(T::Array[Suggestion]) }
        memoize def suggestions_candidate
          SecurityOverviewAnalytics::Dashboards::OrgReposFilterer
            .new(
              organization: @organization,
              allowed_repo_ids_by_feature: \
                unless @allowed_repo_ids.nil?
                  SecurityFeatures.visible_features(@organization).each_with_object({}) do |feature, memo|
                    memo[feature] = @allowed_repo_ids
                  end
                end,
              user: @user,
              user_session: @user_session,
              query: ::Search::Queries::SecurityCenter::QueryParser.new(""),
            )
            .any_feature_repo_metadata_rel
            .then do |rel|
              next rel unless selected_values.present?
              rel.where.not(name: selected_values)
            end
            .then do |rel|
              next rel unless value.present?
              rel.where("name LIKE ?", "%#{value}%")
            end
            .then do |rel|
              if value.present?
                # This puts exact matches first, then sorts by name ASC
                # e.g. ORDER BY `soa_repositories`.`name` = 'github' DESC, `soa_repositories`.`name` ASC
                exact_match = ::SecurityOverviewAnalytics::Repository.arel_table[:name].eq(value)
                rel.order(Arel::Nodes::Descending.new(exact_match)).order(:name)
              else
                rel.order(:name)
              end
            end
            .limit(limit)
            .pluck(:name)
            .map { |name| Suggestion.new(value: name) }
        end
      end
    end
  end
end
