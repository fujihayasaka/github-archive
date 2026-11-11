# typed: strict
# frozen_string_literal: true

module GitHubModels
  module IBlock
    extend T::Helpers

    include Kernel

    interface!

    sig { abstract.returns(String) }
    def reason; end

    sig { abstract.returns(T.nilable(::User)) }
    def actor; end

    sig { abstract.returns(Integer) }
    def actor_id; end

    sig { abstract.returns(T.nilable(::User)) }
    def user; end

    sig { abstract.returns(Integer) }
    def user_id; end

    sig { abstract.returns(T::Boolean) }
    def active?; end

    sig { abstract.returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def created_at; end
  end
end
