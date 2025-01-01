# typed: strict
# frozen_string_literal: true

module Checks
  module ICheckSuite
    extend T::Helpers

    interface!

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(Integer) }
    def repository_id; end

    sig { abstract.returns(String) }
    def head_sha; end

    sig { abstract.returns(ActiveSupport::TimeWithZone) }
    def created_at; end

    sig { abstract.returns(Integer) }
    def github_app_id; end

    sig { abstract.returns(T::Boolean) }
    def actions_app?; end
  end
end
