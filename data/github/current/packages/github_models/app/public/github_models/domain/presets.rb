# typed: strict
# frozen_string_literal: true

module GitHubModels
  class Domain
    class Presets < GH::Domain::Base
      include GitHub::Memoizer

      # Public: How many model presets a user is allowed to have.
      sig { returns Integer }
      def limit_per_user
        Preset::LIMIT_PER_USER
      end

      # Public: Look up a models preset by its slug and optionally by the user who made it.
      sig { params(slug: String, user: T.nilable(::User)).returns(T.nilable(IPreset)) }
      def find(slug:, user: nil)
        scope = Preset
        scope = scope.for_user(user) if user
        scope.find_by(slug: slug)
      end

      # Public: Load JSON representations of a user's model presets.
      sig { params(user: T.nilable(::User)).returns(T::Array[Types::Preset]) }
      def load_payloads(user: nil)
        presets = Preset.for_user(user).order(:name)
        presets.map(&:json_payload)
      end

      # Public: Create a new model preset for a user using the given attributes. Defaults to private if `is_private` is
      # not specified.
      sig do
        params(
          user: T.nilable(::User),
          name: T.nilable(String),
          parameters: T.untyped,
          is_private: T.nilable(T.any(T::Boolean, String))
        ).returns(IPreset)
      end
      def create(user:, name:, parameters:, is_private: nil)
        Preset.create(user: user, name: name, private: is_private.nil? ? true : is_private, parameters: parameters)
      end

      # Public: Update a user's model preset using the given attributes.
      sig do
        params(
          preset: IPreset,
          name: T.nilable(String),
          parameters: T.untyped,
          is_private: T.nilable(T.any(T::Boolean, String))
        ).returns(T::Boolean)
      end
      def update(preset:, name:, parameters:, is_private: nil)
        attrs = { name: name, parameters: parameters }
        attrs[:private] = is_private unless is_private.nil?
        preset.respond_to?(:update) ? T.unsafe(preset).update(attrs) : false
      end

      # Public: Delete a user's model preset.
      sig { params(preset: IPreset).returns(T::Boolean) }
      def destroy(preset)
        return false unless preset.respond_to?(:destroy)
        T.unsafe(preset).destroy
        preset.destroyed?
      end
    end
  end
end
