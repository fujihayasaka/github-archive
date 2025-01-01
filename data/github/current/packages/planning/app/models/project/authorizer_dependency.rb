# typed: false
# frozen_string_literal: true

class Project
  module AuthorizerDependency
    def content_authorizer_for(user:)
      @content_authorizers ||= {}

      operation = new_record? ? :create : :update
      return @content_authorizers.fetch(user) if @content_authorizers.has_key?(user)

      project = self.class == Project ? self : self.project

      @content_authorizers[user] = ContentAuthorizer.authorize(user, :project, operation, project: project)
    end

    def actor_can_modify_projects?(actor)
      content_authorizer_for(user: actor).passed?
    end

    def actor_can_modify_projects(actor: modifying_user)
      unless actor_can_modify_projects?(actor)
        content_authorizer_for(user: actor).errors.each do |error|
          errors.add(:base, error.message)
        end
      end
    end
  end
end
