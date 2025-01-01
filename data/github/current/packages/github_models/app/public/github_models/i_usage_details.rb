# typed: strict
# frozen_string_literal: true

module GitHubModels
  module IUsageDetails
    extend T::Helpers

    include Kernel

    interface!

    sig { abstract.returns(T.nilable(::User)) }
    def user; end

    sig { abstract.returns(Integer) }
    def user_id; end

    sig { abstract.returns(Integer) }
    def auths_count; end

    sig { abstract.returns(T::Boolean) }
    def persisted?; end

    sig { abstract.returns(T::Boolean) }
    def changed?; end
  end
end
