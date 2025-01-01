# typed: strict
# frozen_string_literal: true

module GitHubModels
  module IPreset
    extend T::Helpers

    include Kernel

    interface!

    sig { abstract.params(other_user: T.nilable(::User)).returns(T::Boolean) }
    def belongs_to?(other_user); end

    sig { abstract.returns(T.nilable(::User)) }
    def user; end

    sig { abstract.returns(Integer) }
    def user_id; end

    sig { abstract.returns(T::Boolean) }
    def private?; end

    sig { abstract.returns(GitHubModels::Types::Preset) }
    def json_payload; end

    sig { abstract.returns(T::Boolean) }
    def present?; end

    sig { abstract.returns(T::Boolean) }
    def destroyed?; end

    sig { abstract.returns(::ActiveModel::Errors) }
    def errors; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(String) }
    def parameters; end

    sig { abstract.returns(String) }
    def slug; end
  end
end
