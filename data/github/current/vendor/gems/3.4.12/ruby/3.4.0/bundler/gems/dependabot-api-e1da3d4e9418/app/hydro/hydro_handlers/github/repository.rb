# frozen_string_literal: true

module HydroHandlers
  module GitHub
    class Repository
      attr_reader :owner, :id

      PERMITTED_ATTRIBUTES = %i(
        id
        global_relay_id
        name
        visibility
        parent_id
        default_branch
        primary_language_name
      ).freeze

      def self.from_message(message, owner:)
        attributes = message.value.fetch(:repository).slice(*PERMITTED_ATTRIBUTES).tap do |a|
          a[:node_id] = a.fetch(:global_relay_id)
        end

        new(attributes, owner: owner)
      end

      def initialize(attributes, owner:)
        @id             = attributes.fetch(:id)
        @node_id        = attributes.fetch(:node_id)
        @name           = attributes.fetch(:name)
        @parent_id      = attributes.fetch(:parent_id)
        @visibility     = attributes.fetch(:visibility)
        @language       = attributes.fetch(:primary_language_name)
        @default_branch = attributes.fetch(:default_branch)
        @owner          = owner
      end

      def attributes
        {
          id: @id,
          node_id: @node_id,
          name: @name,
          owner: owner.attributes,
          private: private?,
          language: @language,
          default_branch: @default_branch,
        }
      end

      # These attributes are used to serialize this class into ActiveJob when required
      # so they must match the arguments the initialize method expects
      def raw_attributes
        {
          id: @id,
          node_id: @node_id,
          name: @name,
          parent_id: @parent_id,
          visibility: @visibility,
          primary_language_name: @language,
          default_branch: @default_branch,
        }
      end

      def exists?
        Repo.exists?(github_id: @id)
      end

      def create_repo!
        FindOrCreateRepo.new(github_repo: attributes).run
      end

      def nwo
        owner.login + "/" + @name
      end

      private

      def private?
        @visibility != :PUBLIC
      end
    end
  end
end
