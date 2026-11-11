# typed: strict
# frozen_string_literal: true

module AzureEXP
  module V2
    module Experiments
      # Request-scoped treatment context.
      #
      # Accumulates userParams (randomization IDs) via `add` or `add_participant`,
      # then lazily fetches from TAS on the first `fetch` call.
      #
      # Read path (sub-µs on cache hit):
      #   1. Check process-level Cache (shared across requests within one worker)
      #   2. On miss: call TAS via Client (~5-10ms), store result in Cache
      #   3. Store result in request-local @result for subsequent reads this request
      #
      # If additional participants are added after the first fetch, both the
      # request-local result and the cache entry are invalidated.
      #
      # Usage:
      #
      #   ctx = AzureEXP::V2::Experiments::Context.new(client)
      #   ctx.add_participant(AzureEXP::V2::Experiments::Participant.user(current_user))
      #   ctx.add("region", "us-east")
      #   ctx.fetch("/copilot/header_v2", "control")
      #
      class Context
        extend T::Helpers

        sig { params(client: T.any(AzureEXP::V2::Experiments::Client, AzureEXP::V2::Experiments::NoOpClient)).void }
        def initialize(client)
          @client = T.let(client, T.any(AzureEXP::V2::Experiments::Client, AzureEXP::V2::Experiments::NoOpClient))
          @user_params = T.let({}, T::Hash[String, String])
          @scopes = T.let(nil, T.nilable(T::Array[String]))
          @required_variants = T.let(nil, T.nilable(T::Array[String]))
          @blocked_variants = T.let(nil, T.nilable(T::Array[String]))
          @result = T.let(nil, T.nilable(AzureEXP::V2::Experiments::AssignmentResult))
          @dirty = T.let(false, T::Boolean)
        end

        # Add a raw key-value pair to the userParams hash.
        # Invalidates any cached result if the value changes.
        sig { params(key: String, value: String).void }
        def add(key, value)
          raise ArgumentError, "key must not be empty" if key.empty?
          raise ArgumentError, "value must not be empty" if value.empty?

          if @user_params[key] != value
            @user_params[key] = value
            @dirty = true if @result
          end
        end

        # Add a typed Participant to the userParams hash. Ignores nil so
        # callers can pass Participant.user(current_user) directly without
        # guarding against anonymous traffic (see Participant.user).
        sig { params(participant: T.nilable(AzureEXP::V2::Experiments::Participant)).void }
        def add_participant(participant)
          return if participant.nil?

          add(participant.key, participant.value)
        end

        # Set optional scopes to limit which experiments are evaluated.
        sig { params(scopes: T.nilable(T::Array[String])).void }
        def set_scopes(scopes)
          if @scopes != scopes
            @scopes = scopes
            @dirty = true if @result
          end
        end

        # Set required variants for staff-testing specific flights.
        sig { params(variants: T.nilable(T::Array[String])).void }
        def set_required_variants(variants)
          if @required_variants != variants
            @required_variants = variants
            @dirty = true if @result
          end
        end

        # Set blocked variants for emergency flight shutdown.
        sig { params(variants: T.nilable(T::Array[String])).void }
        def set_blocked_variants(variants)
          if @blocked_variants != variants
            @blocked_variants = variants
            @dirty = true if @result
          end
        end

        # Returns the value of a feature variable, or default_value if the
        # flag is not present, the assignment failed, or no userParams have
        # been added yet.
        #
        # First call checks the process-level cache (sub-µs). On miss,
        # calls TAS (~5-10ms) and stores the result in the cache for
        # future requests on this worker.
        sig { params(flag: String, default_value: String).returns(String) }
        def fetch(flag, default_value)
          resolve.fetch(flag, default_value)
        end

        # Returns the assignment context string for telemetry attribution.
        # Format: "flight-name:allocation-id;..."
        # Returns empty string if no assignment has been fetched yet.
        sig { returns(String) }
        def assignment_context
          resolve.assignment_context
        end

        # Returns the config data version used for the current assignment.
        sig { returns(Integer) }
        def data_version
          resolve.data_version
        end

        # Returns the current userParams hash (read-only snapshot).
        sig { returns(T::Hash[String, String]) }
        def user_params
          @user_params.dup
        end

        private

        # All parameters that affect the assignment, used as the cache key.
        sig { returns(T::Hash[String, T.untyped]) }
        def cache_params
          params = { "user_params" => @user_params }
          params["scopes"] = @scopes if @scopes
          params["required_variants"] = @required_variants if @required_variants
          params["blocked_variants"] = @blocked_variants if @blocked_variants
          params
        end

        sig { returns(AzureEXP::V2::Experiments::AssignmentResult) }
        def resolve
          if @result.nil? || @dirty
            # Check process-level cache first (sub-µs)
            cached = AzureEXP::V2::Experiments::InMemoryCache.instance.get(cache_params)
            if cached
              @result = cached
            else
              # Cache miss: call TAS (~5-10ms), store in process-level cache
              @result = @client.get_assignment(
                @user_params,
                scopes: @scopes,
                required_variants: @required_variants,
                blocked_variants: @blocked_variants,
              )
              AzureEXP::V2::Experiments::InMemoryCache.instance.set(cache_params, @result)
            end
            @dirty = false
          end
          @result
        end
      end
    end
  end
end
