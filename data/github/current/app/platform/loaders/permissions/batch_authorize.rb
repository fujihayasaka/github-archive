# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Permissions
      class BatchAuthorize < Platform::Loader
        def self.load(action:, subject:, actor:, context: {})
          self.for.load({
            action: action,
            subject: subject,
            actor: actor,
            context: context,
          })
        end

        def fetch(requests)
          ::Permissions::Enforcer.batch_authorize(requests: requests)
        end
      end
    end
  end
end
