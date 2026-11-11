# typed: strict
# frozen_string_literal: true

module AppSecurity
  class Domain
    class UserRoles < GH::Domain::Base
      include GH::Domain::DestroyMethods
      BATCH_SIZE = 100

      # Public: Delete user roles by their IDs.
      #
      # When throttling is enabled, deletions are performed in BATCH_SIZE batches.
      # When throttling is disabled, matching roles are deleted directly.
      #
      # ids - An Array of Integer user role IDs to delete.
      # throttle - A Boolean indicating whether to apply throttling. Defaults to true.
      #
      # Returns nothing.
      sig { params(ids: T::Array[Integer], throttle: T::Boolean).void }
      def delete_by_ids(ids, throttle: true) # rubocop:disable Metrics/MethodLength
        return if ids.empty?

        roles_to_delete = UserRole.where(id: ids)

        GH::DualWriter.track do
          if throttle
            roles_to_delete.in_batches(of: BATCH_SIZE) do |batch|
              UserRole.throttle do
                batch.delete_all
              end
            end
          else
            roles_to_delete.delete_all
          end
        end
      end

      # Public: Destroy user roles matching the given conditions in BATCH_SIZE batches.
      #
      # Unlike delete_by_ids, this method runs ActiveRecord callbacks via destroy_all.
      #
      # The GH::Omit type distinguishes that an optional parameter is being omitted,
      # as opposed to nil, because nil might be a legitimate value.
      #
      # Returns an Array of destroyed UserRole records.
      sig do
        params(
          actor_type: T.any(String, T::Array[String], GH::Omit),
          actor_id: T.any(Integer, T::Array[Integer], GH::Omit),
          target_type: T.any(String, T::Array[String], GH::Omit),
          target_id: T.any(Integer, T::Array[Integer], GH::Omit),
          role_id: T.any(Integer, T::Array[Integer], GH::Omit),
        ).returns(T::Array[UserRole])
      end
      def destroy_by_conditions(actor_type: GH::OMIT, actor_id: GH::OMIT, target_type: GH::OMIT, target_id: GH::OMIT, role_id: GH::OMIT) # rubocop:disable Metrics/MethodLength
        conditions = { actor_type:, actor_id:, target_type:, target_id:, role_id: }
        conditions.reject! { |_, v| v == GH::OMIT }
        raise ArgumentError, "At least one condition is required" if conditions.empty?

        roles_to_destroy = UserRole.where(conditions)

        destroyed = T.let([], T::Array[UserRole])
        GH::DualWriter.track do
          roles_to_destroy.in_batches(of: BATCH_SIZE) do |batch|
            UserRole.throttle do
              destroyed.concat(batch.destroy_all)
            end
          end
        end
        destroyed
      end

      # Public: Destroy a single user role record.
      #
      # Runs ActiveRecord callbacks. Wraps the operation in GH::DualWriter.track.
      #
      # record - A UserRole to destroy.
      # raise  - A Boolean indicating whether to raise on failure. Defaults to false.
      #          When true, uses destroy! which raises ActiveRecord::RecordNotDestroyed.
      #          When false, uses destroy which returns the frozen record or false.
      #
      # Returns the destroyed UserRole, or false if destroy failed and raise is false.
      sig { params(record: UserRole, raise: T::Boolean).returns(T.any(UserRole, T::Boolean)) }
      def destroy(record, raise: false)
        GH::DualWriter.track do
          raise ? record.destroy! : record.destroy
        end
      end

      # Public: Update a single user role record's role.
      #
      # Wraps the operation in GH::DualWriter.track.
      #
      # record - A UserRole to update.
      # role   - A Role to set on the record.
      # raise  - A Boolean indicating whether to raise on failure. Defaults to false.
      #          When true, uses update! which raises ActiveRecord::RecordInvalid.
      #          When false, uses update which returns a Boolean.
      #
      # Returns a Boolean indicating success.
      sig { params(record: UserRole, role: Role, raise: T::Boolean).returns(T::Boolean) }
      def update(record, role:, raise: false)
        GH::DualWriter.track do
          raise ? record.update!(role:) : record.update(role:)
        end
      end

      # Called by DestroyDependentRecordsJob when use_domain is enabled.
      sig { override.params(record: ActiveRecord::Base).returns(T::Boolean) }
      def background_destroy(record)
        GH::DualWriter.track do
          !!record.destroy
        end
      end

      # Called by DeleteDependentRecordsJob when use_domain is enabled.
      sig { override.params(ids: T::Array[T.any(Integer, String)]).returns(Integer) }
      def background_delete(ids)
        GH::DualWriter.track do
          UserRole.where(id: ids).delete_all
        end
      end
    end
  end
end
