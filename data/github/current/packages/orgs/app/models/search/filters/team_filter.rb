# typed: true
# frozen_string_literal: true

module Search
  module Filters

    # The TeamFilter is used to limit search results to those where a
    # particular team or teams were mentioned. This class encapsulates the
    # logic of looking up the teams and generating ElasticSearch term filters.
    class TeamFilter < TermFilter

      attr_reader :current_user

      # Create a new TeamFilter.
      #
      # opts - The options Hash
      #   :field - the document field containing the team IDs
      #
      def initialize(opts = {})
        super(opts)
        @current_user = options.fetch(:current_user, nil)
        map_bool_collection
      end

      # This reason can be used when the team filter is invalid.
      def invalid_reason
        @invalid_reason ||=
          "The listed teams cannot be searched either because the teams do not exist or you do not have permission to access them."
      end

      # Internal: Take the boolean collection and convert all the values into
      # team IDs if possible.
      #
      # Returns this filter's boolean colleciton.
      def map_bool_collection
        return bool_collection if defined? @mapped
        @mapped = true

        return bool_collection.clear if current_user.nil?

        # save these off for our validity check
        must_flag     = bool_collection.must?
        must_not_flag = bool_collection.must_not?

        # convert team mention strings to team IDs
        hash = teams
        return bool_collection if hash.nil?

        bool_collection.map_all! { |slug| hash[slug.downcase] }
        bool_collection.uniq!

        # did we specify invalid team slugs?
        @valid = (must_flag     == bool_collection.must?) &&
                 (must_not_flag == bool_collection.must_not?)

        # prune `must_not` team IDs from the `must` and `should` lists
        bool_collection.intersect!
        bool_collection
      end

      # Internal: Convert the team mention strings from the boolean collection
      # into team IDs. We expect the mention string to be the combined slug
      # 'org/team-name'.
      #
      # Returns a Hash mapping team mentions to IDs.
      def teams
        ary = bool_collection.all.map do |str|
          return invalid(str) unless str.include? "/"

          org, slug, *extra = str.downcase.split("/")
          return invalid(str) unless extra.empty?

          team = Team.with_org_name_and_slug(org, slug)
          return invalid(str) unless team && team.organization.member_or_can_view_members?(current_user)

          team
        end

        ary.inject(Hash.new) do |hash, team|
          next hash if team.nil?
          hash[team.combined_slug.downcase] = team.id
          hash
        end
      end

      # Internal: Mark this filter as invalid because the given `team` name is
      # invalid for one reason or another.
      #
      # team - The invalid team name as a String.
      #
      # Returns nil
      def invalid(team)
        @valid = false
        @invalid_reason = "#{team.inspect} is not a valid team name."
        nil
      end

    end  # UserFilter
  end  # Filters
end  # Search
