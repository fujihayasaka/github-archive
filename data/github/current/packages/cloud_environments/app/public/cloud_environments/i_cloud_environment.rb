# typed: strict
# frozen_string_literal: true

module CloudEnvironments
  module ICloudEnvironment
    extend T::Helpers
    interface!

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(String) }
    def guid; end

    sig { abstract.returns(String) }
    def state; end

    sig { abstract.returns(T::Boolean) }
    def provisioned?; end

    sig { abstract.returns(T.nilable(Codespaces::Environment)) }
    def environment_data; end

    sig { abstract.void }
    def deprovision!; end

    sig { abstract.returns(T.nilable(User)) }
    def owner; end

    sig { abstract.returns(T::Boolean) }
    def published?; end

    sig { abstract.returns(T.nilable(Repository)) }
    def repository; end
  end
end
