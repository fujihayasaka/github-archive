# typed: true
# frozen_string_literal: true

module Permissions
  class QueryRouter

    ACTOR_TYPES_WITH_FINE_GRAINED_PERMISSIONS = %w[
      IntegrationInstallation
      OauthAuthorization
      ScopedIntegrationInstallation
    ]

    class FgpQueryDetectedError < ArgumentError; end

    def self.for(subject_types:)
      new(subject_types: subject_types)
    end

    def self.delete_app_permissions_on_actor(actor, entry_point:)
      Permissions::Service.revoke_permissions_granted_on_actor(
        actor_id:   actor.ability_id,
        actor_type: actor.ability_type,
        entry_point: entry_point,
      )
    end

    # Public: delete app permissions for a given subject.
    #
    # subject - The subject Object
    #
    # Returns result of calling given block, or nil.
    def self.delete_app_permissions_on_subject(subject, entry_point:)
      Permissions::Service.revoke_permissions_granted_on_subject(
        subject_id:    subject.id,
        subject_types: subject.resources.class.all_prefixed_subject_types,
        entry_point:   entry_point,
      )
    end

    # Public: A list of all data sources that could possibly store Ability
    # shaped records for the given actor. Use this when you need to query
    # for all abilities records for a given actor, regardless of whether the
    # abilities might be fine-grained, coarse-grained, or both.
    #
    # Returns an Array of Hashes of the form [ { model: , table_name: } ]
    # model is one of Ability or Permission
    # table_name is an Arel SQL node suitable for use in the FROM clause
    # of a SQL statement.
    def self.data_sources_for_actor(actor)
      sources = []
      sources << { model: Ability, table_name: Arel.sql("abilities") }

      if can_have_fine_grained_permissions?(actor_type: actor.ability_type)
        sources << { model: Permission, table_name: Arel.sql("permissions") }
      end

      sources
    end

    # Internal: Tests whether a given subject type matches the pattern we
    # expect for fine-grained permissions, which is a capitalized string with a
    # foward slash in the middle.
    #
    # Returns either match data if it was a fine-grained subject type, or nil
    # if it was not.
    def self.match_fine_grained_subject_type?(subject_type)
      /[A-Z]\w+\/\w*/.match("#{subject_type}")
    end

    # Internal: Only GitHub Apps can have fine grained permissions that are represented
    # by Ability models for now.
    def self.can_have_fine_grained_permissions?(actor_type:)
      ACTOR_TYPES_WITH_FINE_GRAINED_PERMISSIONS.include?(actor_type)
    end

    attr_reader :subject_types

    def initialize(subject_types:)
      @subject_types = Array(subject_types)
    end

    def model(*args)
      if subject_types_in_collab?
        Permission
      else
        Ability
      end
    end

    def subject_types_in_collab?
      subject_types.all? do |subject_type|
        next false unless fine_grained?(subject_type)

        collab_subject_types.any? { |type| type.start_with?(subject_type) }
      end
    end

    # Internal: a list of subject types for which abilities records have been
    # fully migrated to the collab/permissions table.
    #
    # NOTE: As of 2019-03-07, *all* fine-grained permissions have been migrated
    # to the permissions table and this list represents all possible Apps
    # related FGP subject types.
    #
    # Returns an Array of subject types in the form: 'Resource/sub_resource'
    def collab_subject_types
      @collab_subject_types ||= Permissions::ResourceRegistry.all_prefixed_subject_types
    end

    # Internal: Does the given subject_type represent a "fine grained"
    # permssion:
    #
    # E.g.  "Repository/issues" => true
    #       "Repository/" => true (wildcard)
    #       "Repository" => false (coarse grained)
    #
    # Returns a Boolean.
    def fine_grained?(subject_type)
      fine_grained_subject_types.include?(subject_type)
    end

    private

    def fine_grained_subject_types
      @_fine_grained_subject_types ||= subject_types.select do |subject_type|
        self.class.match_fine_grained_subject_type?(subject_type)
      end
    end

    def coarse_grained_subject_types
      subject_types - fine_grained_subject_types
    end
  end
end
