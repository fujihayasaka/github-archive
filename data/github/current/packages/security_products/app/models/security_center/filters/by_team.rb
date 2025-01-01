# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module Filters
    class ByTeam
      extend T::Sig
      include GitHub::SecurityCenter::LoggingHelper

      sig do
        params(
          incl_filters: T.nilable(T::Array[String]),
          excl_filters: T.nilable(T::Array[String]),
          organizations: T.nilable(T::Array[Organization]),
          user: User
        ).void
      end
      def initialize(incl_filters, excl_filters, organizations:, user:)
        @incl_filters = T.let(incl_filters&.uniq, T.nilable(T::Array[String]))
        @excl_filters = T.let(excl_filters&.uniq, T.nilable(T::Array[String]))
        @organizations = T.let(organizations&.uniq || [], T::Array[Organization])
        @user = user
      end

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        return rel if is_empty?
        return rel.none if @organizations.empty?
        rel = where(rel, @incl_filters) if @incl_filters.present?
        rel = where(rel, @excl_filters, neg: true) if @excl_filters.present?
        rel
      end

      sig { returns(T::Boolean) }
      def is_empty?
        @incl_filters.blank? && @excl_filters.blank?
      end

      private

      sig do
        params(
          rel: ActiveRecord::Relation,
          filters: T::Array[String],
          neg: T::Boolean
        ).returns(ActiveRecord::Relation)
      end
      def where(rel, filters, neg: false)
        team_slugs_by_org = team_slugs_by_org(filters)

        visible_teams = @organizations.flat_map do |org|
          org.visible_teams_for(@user).where(slug: team_slugs_by_org[org.display_login.downcase])
        end

        roles = [:admin, :write]
        repo_ids = visible_teams.flat_map { |team| team.direct_or_inherited_repo_ids(action: roles) }.uniq

        if neg
          rel.where.not(repository_id: repo_ids)
        else
          rel.where(repository_id: repo_ids)
        end
      end

      sig { params(filters: T::Array[String]).returns(T::Hash[String, T::Array[String]]) }
      def team_slugs_by_org(filters)
        combined_slugs, slugs = filters.partition { |slug| slug.include?("/") }

        Hash.new { |h, k| h[k] = slugs.dup }.tap do |org_to_team_slugs|
          combined_slugs.each do |combined_slug|
            org_slug, team_slug = combined_slug.split("/", 2)
            org_to_team_slugs[org_slug.downcase] << team_slug unless org_slug.nil?
          end
        end
      end

      instrument_method \
        :where
    end
  end
end
