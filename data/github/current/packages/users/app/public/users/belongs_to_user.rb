# typed: strict
# frozen_string_literal: true

module Users
  module BelongsToUser
    extend T::Helpers

    requires_ancestor { ActiveRecord::Base }

    abstract!

    # The single feature flag that controls all migrations of `belongs_to :user`
    # to `belongs_to_user_via_domain`. When the flag is disabled, callers fall
    # back to the original ActiveRecord `belongs_to :user` association via
    # `belongs_to_domain`'s `super()` path, preserving prior behavior.
    DEFAULT_FEATURE_FLAG = T.let("belongs_to_user_via_domain", String)

    sig { params(base: T::Module[T.anything]).void }
    def self.included(base)
      base.include GH::Associations::BatchMethodAdapters
      super
    end

    module ClassMethods
      extend T::Helpers

      # Replaces `belongs_to :user` (or a custom-named user association) with a
      # domain-backed accessor. The original ActiveRecord `belongs_to` is still
      # declared internally so validations, callbacks (`touch:`), inverse
      # tracking, and other AR features continue to work; the override only
      # changes how the association reader fetches its target when the feature
      # flag is enabled.
      #
      # Options:
      #   feature_flag:        Override the default feature flag string. Pass
      #                        `nil` to always use the domain path (no gating).
      #                        Defaults to `DEFAULT_FEATURE_FLAG`.
      #   relation_name:       Override the association name (default `:user`).
      #   foreign_key:         Override the foreign key (default `:user_id`).
      #   legacy_return_type:  When true (default), return type is
      #                        `T.nilable(::User)` for maximum source
      #                        compatibility. When false, return type is
      #                        `T.nilable(Users::IUser)`.
      #   All remaining options are forwarded to the underlying
      #   `belongs_to relation_name, **options` declaration (e.g. `optional:`,
      #   `required:`, `class_name:`, `inverse_of:`, `strict_loading:`,
      #   `touch:`).
      sig { params(options: T::Hash[Symbol, T.untyped]).void }
      def belongs_to_user_via_domain(options = {})
        feature_flag = if options.key?(:feature_flag)
          options.delete(:feature_flag)
        else
          DEFAULT_FEATURE_FLAG
        end
        legacy_return_type = options.delete(:legacy_return_type)
        legacy_return_type = true if legacy_return_type.nil?
        return_type = legacy_return_type ? T.nilable(::User) : T.nilable(::Users::IUser)
        relation_name = options.delete(:relation_name) || :user
        foreign_key = options.delete(:foreign_key) || :user_id

        T.bind(self, T.class_of(ActiveRecord::Base))
        belongs_to relation_name, **options

        T.unsafe(self).belongs_to_domain(relation_name, foreign_key:, return_type:, feature_flag:, ar_relation: true) do |user_ids|
          Users.domain.by_ids(user_ids)
        end
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
