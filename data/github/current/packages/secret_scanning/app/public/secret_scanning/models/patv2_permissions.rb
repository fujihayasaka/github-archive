# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    class Patv2Permissions
      extend T::Sig

      attr_reader :target_id, :target_type, :permissions, :target_name

      sig do
        params(
          target_id: Integer,
          target_type: Symbol,
          permissions: T::Hash[String, Symbol]
        ).void
      end
      def initialize(target_id, target_type, permissions)
        if target_type != :organization && target_type != :user
          raise ArgumentError, "Invalid target_type. Expected :organization or :user, got #{target_type}"
        end

        @target_id = target_id
        @target_type = target_type
        @permissions = permissions
        @target_name = get_target_name
      end

      sig { returns(T::Array[T::Hash[String, String]]) }
      def scopes_hash
        @permissions.map do |k, v|
          {
            scope: k,
            permission: v.to_s
          }
        end
      end

      private

      sig { returns(String) }
      def get_target_name
        if @target_type == :organization
          org = Organization.find_by(id: @target_id)
          if !org.nil?
            org.name
          else
            ""
          end
        else
          user = User.find_by(id: @target_id)
          if !user.nil?
            user.name
          else
            ""
          end
        end
      end


    end
  end
end
