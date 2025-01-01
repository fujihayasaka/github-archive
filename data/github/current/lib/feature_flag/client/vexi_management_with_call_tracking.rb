# typed: strict
# frozen_string_literal: true

require "vexi_management"

module FeatureFlag::Client
  # This class wraps `VexiManagement::Client` such that it tracks call sites for auditing.
  # It is intended to be used as a drop-in replacement for the original client.
  # The caller information will be stored in a thread-local variable which
  # is being used by the `FeatureFlag::VexiManagementUser` middleware.
  class VexiManagementWithCallTracking < VexiManagement::Client
    VEXI_MANAGEMENT_CALLER_KEY = :vexi_management_caller_service

    sig { params(name: T.any(String, Symbol)).returns(T.nilable(Vexi::FeatureFlag)) }
    def get_feature_flag(name)
      return super(name) unless should_track_calls?

      begin
        track_call_site(caller_locations)
        super(name)
      ensure
        reset_vexi_management_caller
      end
    end

    sig { params(name: T.any(String, Symbol)).void }
    def enable_feature_flag(name)
      return super(name) unless should_track_calls?

      begin
        track_call_site(caller_locations)
        super(name)
      ensure
        reset_vexi_management_caller
      end
    end

    sig { params(name: T.any(String, Symbol)).void }
    def disable_feature_flag(name)
      return super(name) unless should_track_calls?

      begin
        track_call_site(caller_locations)
        super(name)
      ensure
        reset_vexi_management_caller
      end
    end

    sig { params(name: T.any(String, Symbol), actors: T::Array[T.any(String, Vexi::Actor)]).void }
    def add_feature_flag_actors(name, actors)
      return super(name, actors) unless should_track_calls?

      begin
        track_call_site(caller_locations)
        super(name, actors)
      ensure
        reset_vexi_management_caller
      end
    end

    sig { params(name: T.any(String, Symbol), actors: T::Array[T.any(String, Vexi::Actor)]).void }
    def remove_feature_flag_actors(name, actors)
      return super(name, actors) unless should_track_calls?

      begin
        track_call_site(caller_locations)
        super(name, actors)
      ensure
        reset_vexi_management_caller
      end
    end

    sig { params(name: T.any(String, Symbol), percentage: Float).void }
    def set_feature_flag_percentage_of_calls(name, percentage)
      return super(name, percentage) unless should_track_calls?

      begin
        track_call_site(caller_locations)
        super(name, percentage)
      ensure
        reset_vexi_management_caller
      end
    end

    sig { params(name: T.any(String, Symbol), percentage: Float).void }
    def set_feature_flag_percentage_of_actors(name, percentage)
      return super(name, percentage) unless should_track_calls?

      begin
        track_call_site(caller_locations)
        super(name, percentage)
      ensure
        reset_vexi_management_caller
      end
    end

    sig { params(name: T.any(String, Symbol), custom_gate: String).void }
    def add_feature_flag_custom_gate(name, custom_gate)
      return super(name, custom_gate) unless should_track_calls?

      begin
        track_call_site(caller_locations)
        super(name, custom_gate)
      ensure
        reset_vexi_management_caller
      end
    end

    sig { params(name: T.any(String, Symbol), custom_gate: String).void }
    def remove_feature_flag_custom_gate(name, custom_gate)
      return super(name, custom_gate) unless should_track_calls?

      begin
        track_call_site(caller_locations)
        super(name, custom_gate)
      ensure
        reset_vexi_management_caller
      end
    end

    private

    sig { returns(T::Boolean) }
    def should_track_calls?
      FeatureFlag.vexi.enabled?(:vexi_management_caller_tracking, default: false) && !GitHub.single_tenant_enterprise?
    end

    sig { params(locations: T::Array[Thread::Backtrace::Location]).void }
    def track_call_site(locations)
      # Filter out sorbet-runtime to normalize the call stack
      filtered_stack = locations.reject { |l| l.path&.include?("sorbet-runtime") }
      # The first frame after filtering should be the direct caller of the Vexi management method
      caller_location = filtered_stack[0]
      return if caller_location.nil? || caller_location.path.nil?

      relative_file_path = Pathname.new(caller_location.path).relative_path_from(Rails.root).to_s
      logical_caller_service = GitHub.serviceowners.service_for_path(relative_file_path, prefix: true)

      if logical_caller_service
        set_vexi_management_caller(logical_caller_service)
      end
    rescue StandardError => ex
      # If development, test or CI re-raise the exception.
      if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test? || ENV["GITHUB_CI"]
        raise ex
      end

      Failbot.report(
        "code.namespace": self.class.name,
        "code.function": "track_call_site",
        "exception.message": ex.message,
      )
    end

    sig { params(logical_caller_service: String).void }
    def set_vexi_management_caller(logical_caller_service)
      Thread.current[VEXI_MANAGEMENT_CALLER_KEY] = logical_caller_service
    end

    sig { void }
    def reset_vexi_management_caller
      Thread.current[VEXI_MANAGEMENT_CALLER_KEY] = nil
    end
  end
end
