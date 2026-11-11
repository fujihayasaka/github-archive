# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PushAllowances < Resolvers::Base
      type Connections::PushAllowance, null: false

      def resolve(**arguments)
        context[:permission].typed_can_access?("BranchProtectionRule", @object).then do |can_access|
          if !can_access
            ArrayWrapper.new
          else
            @object.async_repository.then do |repository|
              repository.async_organization.then do
                actors = @object.authorized_actors.map { |actor| async_resolve_actor(actor) }

                Promise.all(actors).then do |resolved_actors|
                  push_allowances = resolved_actors.map do |actor|
                    Models::PushAllowance.new(@object, actor)
                  end
                  ArrayWrapper.new(push_allowances)
                end
              end
            end
          end
        end
      end

      private

      def async_resolve_actor(actor)
        actor.is_a?(::IntegrationInstallation) ? actor.async_integration : actor
      end
    end
  end
end
