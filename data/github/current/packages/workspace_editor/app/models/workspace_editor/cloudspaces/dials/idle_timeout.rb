# typed: strict
# frozen_string_literal: true
module WorkspaceEditor
  module Cloudspaces
    module Dials
      class IdleTimeout < Codespaces::Dial

        validates :value,
                  numericality: { only_integer: true, greater_than_or_equal_to: 15, less_than_or_equal_to: 120 }

        sig { override.returns(String) }
        def key
          "hadron_cloudspaces_idle_timeout_minutes"
        end

        sig { override.returns(String) }
        def default_value
          "15"
        end

        sig { override.returns(String) }
        def description
          "This value sets the idle timeout for workspace editor cloudspaces.
          For example, when this dial's value is set to 15, a user's
          cloudspace will be automatically shut down after 15 minutes."
        end

        private

        sig { params(value: String).returns(Integer) }
        def transform_value_to_use(value)
          value.to_i
        end
      end
    end
  end
end
