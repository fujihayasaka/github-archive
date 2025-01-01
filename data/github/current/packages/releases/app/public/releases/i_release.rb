# typed: strict
# frozen_string_literal: true

module Releases
  module IRelease
    extend T::Helpers

    include Kernel

    abstract!
    sig { abstract.returns(T::Boolean) }
    def new_record?; end

    sig { abstract.returns(String) }
    def notes?; end

    sig { abstract.returns(T::Boolean) }
    def viewable?; end

    sig { abstract.returns(String) }
    def tag_name; end

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(String) }
    def permalink; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(T::Boolean) }
    def draft?; end

    sig { abstract.returns(T::Boolean) }
    def prerelease?; end

    sig { abstract.returns(Time) }
    def created_at; end

    sig { abstract.returns(Time) }
    def published_at; end

    sig { abstract.returns(T::Boolean) }
    def published?; end

    sig { abstract.returns(Integer) }
    def repository_id; end

    sig { abstract.returns(Integer) }
    def author_id; end

    sig { abstract.returns(Repository) }
    def repository; end

    sig { abstract.returns(String) }
    def body; end

    sig { abstract.returns(String) }
    def target_commitish; end
  end
end
