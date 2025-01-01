# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  module Users
    module TechnicalPreview
      extend T::Helpers
      include Copilot::Users::Signatures

      abstract!

      sig { override.returns(T::Boolean) }
      def technical_preview_user_lost_access?
        GitHub.tracer.in_span("copilot.is_technical_preview_user", attributes: { "gh.user.id" => user_object.id }) do |_span|
          tp_user = technical_preview_user

          return false unless tp_user

          # They did not lose access if they subscribed.
          return false if tp_user.subscribed

          # All technical preview users that have not subscribed have lost access
          # by now (last one created 2022-08-11).
          true
        end
      end

      # This method checks whether the user is a member of the technical preview.
      sig { override.returns(T::Boolean) }
      def is_technical_preview_user?
        GitHub.tracer.in_span("copilot.is_technical_preview_user", attributes: { "gh.user.id" => user_object.id }) do |_span|
          async_is_technical_preview_user?.sync
        end
      end

      sig { override.returns(Promise[T::Boolean]) }
      def async_is_technical_preview_user?
        async_technical_preview_user.then do |tp_user|
          tp_user.present?
        end
      end

      sig { override.returns(T.nilable(Copilot::TechnicalPreviewUser)) }
      def technical_preview_user
        async_technical_preview_user.sync
      end

      sig { override.returns(Promise[T.nilable(Copilot::TechnicalPreviewUser)]) }
      def async_technical_preview_user
        ActiveRecord::Base.connected_to(role: :reading) do
          Platform::Loaders::ActiveRecord.load(
            ::Copilot::TechnicalPreviewUser,
            user_object.id,
            column: :user_id,
          )
        end
      end
    end
  end
end
