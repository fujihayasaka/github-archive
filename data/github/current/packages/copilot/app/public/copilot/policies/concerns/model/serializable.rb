# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Concerns
      module Model
        module Serializable
          extend T::Helpers
          include Copilot::Policies::Model

          abstract!

          sig { override.returns(T.nilable(Copilot::Types::Models::Publisher)) }
          def publisher
            nil
          end

          sig { override.returns(T.nilable(Copilot::Types::Models::Category)) }
          def category
            nil
          end

          sig { override.params(user: Copilot::User, entity: Copilot::Types::CopilotEntity).returns(Copilot::Types::Models::Serialized) }
          def serialize(user, entity)
            Copilot::Types::Models::Serialized.new(
              name: config_name,
              displayName: display_name,
              publisher:,
              category:,
              value: effective_value(user),
              isPreview: preview?(entity),
            )
          end
        end
      end
    end
  end
end
