# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  module Filters
    class Team
      extend T::Sig

      include GitHub::Memoizer

      sig { params(user: User, org: Organization, filter_hash: T::Hash[String, T.untyped]).void }
      def initialize(user, org, filter_hash)
        @user = user
        @org = org
        @filter_hash = filter_hash
      end

      sig { returns(T::Array[Integer]) }
      def apply
        return [] unless team_filters_present?

        teams = @org.visible_teams_for(@user)
        if @filter_hash["team"]
          teams = teams.where(name: @filter_hash["team"])
        end
        if @filter_hash["-team"]
          teams = teams.where.not(name: @filter_hash["-team"])
        end

        roles = [:admin, :write]
        teams.flat_map { |team| team.direct_or_inherited_repo_ids(action: roles) }.uniq
      end

      def team_filters_present?
        team_names = @filter_hash["team"] || @filter_hash["-team"]
        team_names.present?
      end
    end
  end
end
