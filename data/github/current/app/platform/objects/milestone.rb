# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Milestone < Platform::Objects::Base
      description "Represents a Milestone object on a given repository."

      include Platform::Authorization::ReauthorizeScopedObjects

      implements_node templates: [[:rm, :repo_id, :milestone_id]], as: "MI", ready_date: "2021-07-16" do |milestone|
        {
          prefix: :rm,
          repo_id: milestone.repository_id,
          milestone_id: milestone.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, milestone)
        permission.async_repo_and_org_owner(milestone).then do |repo, org|
          permission.access_allowed?(:get_milestone, resource: milestone, repo: repo, allow_integrations: true, current_org: org, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::Closable
      implements Interfaces::UniformResourceLocatable

      field :title, String, "Identifies the title of the milestone.", null: false
      field :description, String, "Identifies the description of the milestone.", null: true

      field :description_html, String, null: true, description: "The HTML rendered description of the milestone using GitHub Flavored Markdown."
      def description_html
        return nil unless @object.description.present?
        GitHub::Goomba::MarkdownPipeline.to_html(@object.description)
      end

      field :number, Integer, "Identifies the number of the milestone.", null: false
      field :due_on, Scalars::DateTime, "Identifies the due date of the milestone.", null: true
      field :state, Enums::MilestoneState, "Identifies the state of the milestone.", null: false
      field :progress_percentage, Float, description: "Identifies the percentage complete for the milestone", null: false

      field :creator, description: "Identifies the actor who created the milestone.", resolver: Resolvers::ActorCreatedBy

      field :repository, Objects::Repository, method: :async_repository, description: "The repository associated with this milestone.", null: false

      updated_at_field
      created_at_field

      field :issues, resolver: Resolvers::Issues, description: "A list of issues associated with the milestone.", connection: true

      field :pull_requests, resolver: Resolvers::MilestonePullRequests, description: "A list of pull requests associated with the milestone.", connection: true

      url_fields description: "The HTTP URL for this milestone" do |milestone|
        milestone.async_repository.then do |repository|
          repository.async_owner.then do |owner|
            template = Addressable::Template.new("/{owner}/{name}/milestone/{number}")
            template.expand(
              owner: owner.display_login,
              name: repository.name,
              number: milestone.number,
            )
          end
        end
      end

      def self.load_from_params(params)
        Objects::Repository.load_from_params(params).then do |repository|
          repository && Loaders::MilestoneByNumber.load(repository.id, params[:number].to_i)
        end
      end
    end
  end
end
