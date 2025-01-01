# typed: strict
# frozen_string_literal: true

module DefaultAndCustomModels
  # Public: Represents an AI model, either a default one offered by GitHub or a custom model hosted elsewhere that was
  # added by a user.
  module IModel
    extend T::Helpers

    include Kernel

    interface!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    # Public: Returns a model representation that is suitable for the frontend to render in the playground, either in
    # a repository or in Marketplace.
    sig { abstract.returns(DefaultAndCustomModels::Types::Model) }
    def to_model; end

    sig { abstract.returns(DefaultAndCustomModels::Types::RepoModel) }
    def to_repository_model; end

    sig { abstract.returns(DefaultAndCustomModels::Types::ModelSchema) }
    def to_schema; end

    sig { abstract.returns(T.nilable(String)) }
    def name; end

    sig { abstract.returns(T.nilable(String)) }
    def friendly_name; end

    sig { abstract.returns(T.nilable(String)) }
    def original_name; end

    sig { abstract.returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def created_at; end

    sig { abstract.returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def updated_at; end

    sig { abstract.returns(String) }
    def slug; end

    sig { abstract.returns(T.nilable(String)) }
    def task; end

    sig { abstract.params(user: T.nilable(::User)).returns(T::Boolean) }
    def readable_by?(user); end

    sig { abstract.returns(T.nilable(String)) }
    def logo_url; end

    sig { abstract.returns(T.nilable(String)) }
    def registry; end

    sig { abstract.returns(T::Boolean) }
    def destroyed?; end

    sig { abstract.returns(Symbol) }
    def event_prefix; end
  end
end
