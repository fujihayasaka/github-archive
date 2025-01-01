# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryTopic < Platform::Objects::Base
      description "A repository-topic connects a repository to a topic."

      implements_node templates: [[:rt, :repo_id, :repository_topic_id]], as: "RT", ready_date: "2021-07-02" do |repository_topic|
        {
          prefix: :rt,
          repo_id: repository_topic.repository_id,
          repository_topic_id: repository_topic.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, repo_topic)
        repo_topic.async_repository.then do |repo|
          permission.typed_can_access?("Repository", repo)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      scopeless_tokens_as_minimum

      implements Interfaces::UniformResourceLocatable

      url_fields description: "The HTTP URL for this repository-topic." do |repo_topic, _arguments, _context|
        repo_topic.async_topic.then do |topic|
          if GitHub.enterprise?
            repo_topic.async_repository.then do |repo|
              repo.async_owner.then do |owner|
                template_args = { topic: topic.name }
                template = "/search?q=topic%3A{topic}"
                if owner.organization?
                  template += "+org%3A{org}"
                  template_args[:org] = owner.display_login
                end
                template += "+fork%3Atrue" if repo.fork?
                template += "&type=Repositories"
                Addressable::Template.new(template).expand template_args
              end
            end
          else
            Addressable::Template.new("/topics/{topic}").expand(topic: topic.name)
          end
        end
      end

      field :topic, Objects::Topic, method: :async_topic, description: "The topic.", null: false
    end
  end
end
