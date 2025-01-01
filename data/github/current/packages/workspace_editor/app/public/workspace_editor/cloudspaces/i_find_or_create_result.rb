# typed: strict
# frozen_string_literal: true

module WorkspaceEditor
  module Cloudspaces
    module IFindOrCreateResult
      extend T::Helpers
      include Kernel

      interface!

      sig { abstract.returns(ICloudspace) }
      def workspace_editor_cloudspace; end

      sig { abstract.returns(T.nilable(Codespaces::Environment)) }
      def env; end

      sig { abstract.returns(T::Boolean) }
      def found?; end
    end
  end
end
