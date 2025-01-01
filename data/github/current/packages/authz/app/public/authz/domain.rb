# typed: strict
# frozen_string_literal: true

module Authz
  class Domain < GH::Domain::Base
    include SorbetTypes

    accessor UserRoles

    # Public: check if the actor is granted the provided permission against the subject
    # Returns an boolean indicating if access is allowed and if the check was indeterminate.
    sig do
      params(
        actor: Actor,
        permission: Symbol,
        subject: Subject)
      .returns(T::Boolean)
      .checked(:always).on_failure(:raise)
    end
    def check_allowed(actor, permission, subject)
      start_time = GitHub::Dogstats.monotonic_time
      if actor.can_have_granular_permissions?
        programmatic_actor_check_single(actor, permission, subject)
      else
        user_check_single(T.cast(actor, User), permission, subject)
      end
    ensure
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("authz.domain.check_allowed", elapsed, tags: [
        "success:#{$!.nil?}",
        "permission:#{permission}",
        "actor_type:#{actor.class.name}",
        "subject_type:#{subject.class.name}"])
    end


    # Public: check if an actor is granted the provided permissions against a subject
    # Returns an T::Hash[Symbol, T::Boolean] mapping each permission to a boolean indicating if access is allowed
    sig do
      params(
        actor: Actor,
        permissions: T::Array[Symbol],
        subject: Subject)
      .returns(T::Hash[Symbol, T::Boolean])
      .checked(:always).on_failure(:raise)
    end
    def check_multiple_permissions(actor, permissions, subject)
      start_time = GitHub::Dogstats.monotonic_time
      requests = permissions.uniq.map { |permission| Request.new(actor: actor, permission: permission, subject: subject) }

      results = if actor.can_have_granular_permissions?
        programmatic_actor_check_batch(requests)
      else
        user_check_batch(requests)
      end

      results.map do |request, is_allowed|
        [request.permission, is_allowed]
      end.to_h
    ensure
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("authz.domain.check_multiple_permissions", elapsed, tags: [
        "success:#{$!.nil?}",
        "permission_count:#{permissions.count}",
        "actor_type:#{actor.class.name}",
        "subject_type:#{subject.class.name}"])
    end

    private

    sig do
      type_parameters(:R)
      .params(
        span_name: String,
        block: T.proc.params(span: T.untyped).returns(T.type_parameter(:R))
      ).returns(T.type_parameter(:R))
    end
    def with_tracing_span(span_name, &block)
      GitHub.tracer.in_span("authz.domain.#{span_name}", kind: :internal) do |span|
        yield span
      end
    end

    sig do
      params(
        actor: Actor,
        permission: Symbol,
        subject: Subject)
      .returns(T::Boolean)
      .checked(:always).on_failure(:raise)
    end
    def programmatic_actor_check_single(actor, permission, subject)
      with_tracing_span("programmatic_actor_check_single") do |_span|
        request = Request.new(actor:, permission:, subject:)
        T.must(programmatic_actor_check_batch([request]).values.first)
      end
    end

    sig do
      params(requests: T::Array[Request])
      .returns(T::Hash[Request, T::Boolean])
      .checked(:always).on_failure(:raise)
    end
    def programmatic_actor_check_batch(requests)
      with_tracing_span("programmatic_actor_check_batch") do |_span|
        assert_programmatic_access_configured(requests)

        requests.map do |req|
          check_method = req.fine_grained_permission.programmatic_access_check_for(req.subject)
          result = T.cast(check_method.call(req.actor), T::Boolean)
          [req, result]
        end.to_h
      end
    end

    sig { params(requests: T.any(T::Array[Request], Request)).void }
    def assert_programmatic_access_configured(requests)
      with_tracing_span("assert_programmatic_access_configured") do |_span|
        fgps = Array.wrap(requests).map(&:fine_grained_permission)
        unsupported = Array.wrap(fgps).reject { |fgp| fgp.supports_programmatic_access? }
        if unsupported.any?
          list_string = unsupported.map { |fgp| "'#{fgp.action}'" }.join(", ")
          raise ArgumentError.new("The following FGPs are not configured for programmatic access: #{list_string}")
        end
      end
    end

    sig do
      params(
        actor: Actor,
        permission: Symbol,
        subject: Subject)
      .returns(T::Boolean)
      .checked(:always).on_failure(:raise)
    end
    def user_check_single(actor, permission, subject)
      with_tracing_span("user_check_single") do |_span|
        request = Request.new(actor:, permission:, subject:)
        result = user_check_batch([request])
        T.must(result.values.first)
      end
    end

    sig do
      params(domain_requests: T::Array[Request])
      .returns(T::Hash[Request, T::Boolean])
      .checked(:always).on_failure(:raise)
    end
    def user_check_batch(domain_requests)
      with_tracing_span("user_check_batch") do |_span|
        authzd_req_to_domain_req = domain_requests.map { |domain_req| [domain_req.authzd_request_hash, domain_req] }.to_h
        authzd_requests = authzd_req_to_domain_req.keys
        batch_response = Permissions::Enforcer.batch_authorize(requests: authzd_requests)

        indeterminates = batch_response.responses.select { |result| result.indeterminate? }
        if indeterminates.any?
          messages = indeterminates.map { |result| "Reason: #{result.reason}\nError: #{result.error&.message}" }.join("\n")
          raise IndeterminateError.new("Indeterminate response(s) from authzd.\n#{messages}")
        end

        authzd_requests.map do |authzd_req|
          [T.must(authzd_req_to_domain_req[authzd_req]), batch_response[authzd_req].allow?]
        end.to_h
      end
    end
  end
end
