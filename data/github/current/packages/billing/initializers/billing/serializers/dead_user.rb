# typed: strict
# frozen_string_literal: true

module Billing
  module Serializers
    class DeadUser < ActiveJob::Serializers::ObjectSerializer

      sig { override.params(argument: T.untyped).returns(T::Boolean) }
      def serialize?(argument)
        argument.is_a?(Billing::DeadUser)
      end

      sig { override.params(user: Billing::DeadUser).returns(T::Hash[T.untyped, T.untyped]) }
      def serialize(user)
        super({
          "id" => user.id,
          "login" => user.display_login,
          "billing_email" => user.billing_email,
          "created_at" => user.created_at,
          "user_type" => user.user_type,
         })
      end

      sig { override.params(hash: T::Hash[T.untyped, T.untyped]).returns(Billing::DeadUser) }
      def deserialize(hash)
        Billing::DeadUser.new do |user|
          user.id            = hash["id"]
          user.login         = hash["login"]
          user.billing_email = hash["billing_email"]
          user.created_at    = hash["created_at"]
          user.user_type     = hash["user_type"]
        end
      end
    end
  end
end

Rails.application.config.active_job.custom_serializers << Billing::Serializers::DeadUser
