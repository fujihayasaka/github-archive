# typed: strict
# frozen_string_literal: true

class Integration
  class UninstallService

    class Result < T::Struct
      const :success, T::Boolean
      const :message, T.nilable(String)

      sig { params(message: String).returns(Result) }
      def self.success(message)
        new(success: true, message: message)
      end

      sig { params(message: String).returns(Result) }
      def self.failure(message)
        new(success: false, message: message)
      end

      sig { returns(T::Boolean) }
      def success?
        success
      end
    end

    sig { params(integration: Integration, current_user: User, staff_actor: T::Boolean).returns(Result) }
    def self.uninstall_all(integration:, current_user:, staff_actor: false)
      new(integration: integration, current_user: current_user, staff_actor: staff_actor).uninstall_all
    end

    sig { params(integration: Integration).returns(Result) }
    def self.cancel_uninstall_all(integration:)
      begin
        Integration.release_bulk_uninstalls_lock(integration)
        Result.success("Successfully cancelled uninstalling all installations.")
      rescue StandardError => e
        Failbot.report(e)
        Result.failure("Failed to cancel uninstalling all installations.")
      end
    end

    sig { params(integration: Integration, current_user: User, staff_actor: T::Boolean).void }
    def initialize(integration:, current_user:, staff_actor: false)
      @integration = integration
      @current_user = current_user
      @staff_actor = staff_actor
    end

    sig { returns(Result) }
    def uninstall_all
      if Integration.locked_for_bulk_uninstalls?(@integration)
        Result.failure("A bulk uninstall is already in progress for this integration.")
      elsif Integration.lock_for_bulk_uninstalls(@integration)
        enqueue_bulk_uninstall
        Result.success("A job has been enqueued to uninstall all installations of #{@integration.slug}.")
      else
        Result.failure("Failed to enqueue an uninstall job.")
      end
    end

    private

    sig { void }
    def enqueue_bulk_uninstall
      BulkUninstallIntegrationInstallationsJob.perform_later(
        @current_user.id,
        @integration.id,
        staff_actor: @staff_actor
      )
    end
  end
end
