# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeOfConduct < Platform::Objects::Base

      implements_node templates: [[:rcoc, :repo_id, :code_of_conduct_id], [:coc, :code_of_conduct_id]], as: "COC", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |code_of_conduct|
        if code_of_conduct.instance_of?(::CodeOfConduct)
          {
            prefix: :coc,
            code_of_conduct_id: code_of_conduct.id
          }
        else
          code_of_conduct.async_repository.then do |repo|
            {
              prefix: :rcoc,
              repo_id: repo.id,
              code_of_conduct_id: code_of_conduct.id
            }
          end
        end
      end

      description "The Code of Conduct for a repository"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, coc)
        return Promise.resolve(true) if coc.instance_of?(::CodeOfConduct)
        repo = coc.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:get_code_of_conduct, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        return Promise.resolve(true) if object.instance_of?(::CodeOfConduct)
        permission.typed_can_see?("Repository", object.repository)
      end

      def self.load_from_next_global_id(parsed_id)
        if parsed_id.parts[:repo_id]
          load_code_of_conduct(parsed_id.parts[:repo_id])
        else
          load_code_of_conduct(parsed_id.parts[:code_of_conduct_id])
        end
      end

      def self.load_from_global_id(id)
        load_code_of_conduct(id)
      end

      def self.load_code_of_conduct(id)
        coc = ::CodeOfConduct.find(id)
        return Promise.resolve(coc) if coc

        Repository.load_from_global_id(id).then do |repo|
          next nil unless repo
          repo.async_network.then do
            repo.code_of_conduct
          end
        end
      end

      scopeless_tokens_as_minimum

      field :key, String, "The key for the Code of Conduct", null: false, method: :legacy_key
      field :name, String, "The formal name of the Code of Conduct", null: false
      field :body, String, "The body of the Code of Conduct", null: true

      url_fields description: "The HTTP URL for this Code of Conduct", null: true do |coc|
        coc.url
      end

      # TODO: Break RepositoryCodeOfConduct into its own GraphQL Object. See https://git.io/fh1vQ
      field :repository, Repository, "The Repository containing the Code of Conduct", null: true, visibility: :internal

      def repository
        @object.repository if @object.respond_to?(:repository)
      end
    end
  end
end
