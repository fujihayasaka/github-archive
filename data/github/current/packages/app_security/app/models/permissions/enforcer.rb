# typed: true
# frozen_string_literal: true

module Permissions
  class Enforcer
    include Scientist # for instance methods
    extend Scientist  # for class methods

    class AttrBuilder
      def initialize
        @attrs = {}
      end

      def add(new_attrs)
        if new_attrs.is_a?(Array)
          new_attrs.each do |new_attr|
            @attrs[new_attr.id.to_s] = new_attr
          end
        else
          @attrs[new_attrs.id.to_s] = new_attrs
        end
      end

      def attrs
        @attrs.values
      end
    end

    def initialize
      @attrs_for_subject = Hash.new do |hash, subject|
        hash[subject] = attrs_for_subject(subject).freeze
      end
      @attrs_for_actor = Hash.new do |hash, actor|
        hash[actor] = attrs_for_actor(actor).freeze
      end
      @attrs_for_actor_by_subject_type_and_id = Hash.new do |hash, actor|
        hash[actor] = Hash.new do |hash, subject_type|
          hash[subject_type] = attrs_for_actor_by_subject_type_and_id(actor, subject_type)
        end
      end
    end

    # Public: Enforce access for an actor to a subject based on the action and
    # context.
    #
    # Returns an Authzd::Response
    def self.authorize(action:, subject:, actor:, context: {}, options: {})
      start = Time.now
      attrs = attrs_for(action: action, subject: subject, actor: actor, context: context)
      authz_request = Authzd::Proto::Request.new(attributes: attrs)

      result = nil
      cache_key = Enforcer.cache_key(authzd_request: authz_request)
      cached = PermissionCache.get(cache_key) unless cache_key.nil? # check if key is cached

      cache_status = cached.nil? ? "miss" : "hit"
      GitHub.dogstats.increment("ability.cache", tags: ["result:#{cache_status}", "namespace:authzd_single"])

      result = cached

      if result.nil?
        result = Permissions::Authorizer.authorize(
          authz_request,
          options,
        )

        cache_key = Enforcer.cache_key(authzd_request: authz_request)
        PermissionCache.set(cache_key, result) if cache_key && Enforcer.cache_result?(result&.decision)
      end

      # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      raise_on_error(result, action: action, attributes: attrs) unless Rails.env.production?
      GitHub.dogstats.distribution("authzd.client.enforcer.authorize", (Time.now - start) * 1_000,
        tags: ["action:#{action}"])
      result
    end

    # requests - an array of hashes with attributes
    #
    # Returns an Authzd::Proto::BatchDecision, which holds Authorizer
    # requests is an array of hashes with keys action, subject, actor, and
    # context
    def self.batch_authorize(requests:)
      new.batch_authorize(requests: requests)
    end

    def batch_authorize(requests:)
      @requests = requests

      start = Time.now
      enforcer_request_to_authzd_request = {}
      authzd_reqs = requests.map do |request|
        attrs = attrs_for(action: request[:action],
                          subject: request[:subject],
                          actor: request[:actor],
                          context: request[:context] || {})

        authzd_request = Authzd::Proto::Request.new(attributes: attrs)
        enforcer_request_to_authzd_request[request] = authzd_request
        authzd_request
      end

      uncached_authzd_requests, cached_results, batch_result = get_cached_requests(authzd_reqs)

      # call authzd with remaining uncached requests if any
      if !batch_result
        batch_request = Authzd::Proto::BatchRequest.new(requests: uncached_authzd_requests)
        batch_result = Permissions::Authorizer.batch_authorize(batch_request)
      end

      self.class.raise_on_error(batch_result) unless Rails.env.production? || Rails.env.test?

      requests.each do |request|
        authzd_request = enforcer_request_to_authzd_request[request]
        if cached_result = cached_results[authzd_request]
          batch_result.map[request] = cached_result
        else
          # FIXME not sure if this is a good idea.
          # The enforcer abstracts the Authzd::Proto::Request away, so it'd make sense to
          # allow getting the Authzd::Proto::Decision for a given enforcer request.
          # This adds to the map those enforcer requests as key. As a consequence,
          # batch_result.map will ne filled with the same decision with 2 different keys.
          batch_result.map[request] = batch_result[authzd_request]
          cache_key = Enforcer.cache_key(authzd_request: authzd_request)
          PermissionCache.set(cache_key, batch_result[authzd_request]) if cache_key && Enforcer.cache_result?(batch_result[authzd_request]&.decision)
        end

      end
      GitHub.dogstats.distribution("authzd.client.enforcer.batch_authorize", (Time.now - start) * 1_000)
      batch_result
    end

    def self.attrs_for(**args)
      T.unsafe(new).attrs_for(**args)
    end

    def attrs_for(action:, subject:, actor:, context: {})
      start = Time.now

      if use_ability_delegate?(actor)
        actor = actor.ability_delegate
      end

      attrs = AttrBuilder.new

      # enables authzd verbose output in development / test
      attrs.add(coerce_attr("_debug_", true)) unless Rails.env.production?

      attrs.add(coerce_attr("action", action))

      # version_for should not be called if version is set in context because
      # it raises errors in cases where callsites must provide the version themselves
      version = context.fetch(:version, false) || Permissions::PolicyVersion.version_for(action:, subject:)
      attrs.add(coerce_attr(Permissions::PolicyVersion::VERSION_ATTRIBUTE, version))

      if subject
        attrs.add(@attrs_for_subject[subject])
        attrs.add(subject.permissions_wrapper.serialized_actor_attributes(actor))

        if subject.is_a?(Repository)
          if context.fetch(:considers_site_admin, nil).nil?
            attrs.add(coerce_attr("considers_site_admin", false))
          end
        elsif subject.is_a?(Marketplace::Listing)
          attrs.add(coerce_attr("user.biztools_user", actor.biztools_user?))
        end
      end

      attrs.add(@attrs_for_actor[actor])

      if actor.is_a?(User)
        if repo = subject.try(:repository)
          if @requests.present?
            attrs.add(@attrs_for_actor_by_subject_type_and_id[actor][:repository][repo.id])
          else
            attrs.add(coerce_attr("user.staff_unlock", actor.has_unlocked_repository?(repo)))
          end
        end
      end

      context.except(:version).each_pair do |key, value|
        attrs.add(coerce_attr(key, value))
      end

      GitHub.dogstats.distribution("authzd.client.enforcer.attributes.total.dist", (Time.now - start) * 1_000, tags: ["action:#{action},unique_experiment:true"])

      attrs.attrs
    end

    def attrs_for_subject(subject)
      subject.permissions_wrapper.serialized_subject_attributes
    end

    def attrs_for_actor_by_subject_type_and_id(actor, subject_type)
      attrs = Hash.new { |hash, subject_id| hash[subject_id] = [] }

      if actor.is_a?(User) && subject_type == :repository
        repos = @requests.map { |r| r[:subject].try(:repository) }.compact.uniq { |repo| repo.id }

        Promise.all(repos.map do |repo|
          actor.async_has_unlocked_repository?(repo).then do |has_unlocked|
            attrs[repo.id] << coerce_attr("user.staff_unlock", has_unlocked)
          end
        end).sync
      end

      attrs
    end

    def attrs_for_actor(actor)
      attrs = []

      if use_ability_delegate?(actor)
        actor = actor.ability_delegate
      end

      if actor
        attrs << coerce_attr("actor.type", actor.class.name)
        attrs << coerce_attr("actor.id", actor.id)
        case actor
        when IntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation
          case actor
          when ScopedIntegrationInstallation
            attrs << coerce_attr("installation.parent.id", actor.integration_installation_id)
          else
            attrs << coerce_attr("installation.parent.id", nil)
          end

          attrs << coerce_attr("installation.integration.id", actor.integration_id)
          attrs << coerce_attr("installation.target.id", actor.target_id)
          attrs << coerce_attr("installation.target.type", actor.target_type)
        when GlobalIntegrationInstallation
          attrs << coerce_attr("installation.integration.id", actor.integration_id)
        when Integration
          attrs << coerce_attr("installation.integration.id", actor.id)
        when User
          attrs << coerce_attr("github.email_verification.enabled", GitHub.email_verification_enabled?)
          attrs << coerce_attr("user.id", actor.id)
          attrs << coerce_attr("user.site_admin", actor.site_admin?)
          attrs << coerce_attr("actor.spammy", actor.spammy?)
          attrs << coerce_attr("actor.suspended", actor.suspended?)
        end
      else
        attrs << coerce_attr("actor.id", nil)
        attrs << coerce_attr("actor.type", nil)
      end

      if actor.respond_to?(:authzd_proto_attributes)
        attrs += actor.authzd_proto_attributes
      end

      attrs
    end

    def coerce_attr(key, value)
      Authzd::Proto::Attribute.wrap(key, value)
    end

    def use_ability_delegate?(actor)
      return false unless actor

      # PublicKey doesn't have abilities directly, rather abilities are
      # delegated to the User that owns the PublicKey, so a user's public keys
      # get the permissions of the user.
      return true if actor.is_a?(PublicKey)

      # Bot type actors don't have direct permissions. We should attempt
      # to use the "hydrated" fine-grained actor that is loaded instead.
      #
      # For example an IntegrationInstallation.
      return true if actor.try(:bot?)

      false
    end

    # Used to make authzd errors more obvious in dev/test by failing loud
    def self.raise_on_error(result, action: "", attributes: [])
      # super-hack: workaround to a NOT_APPLICABLE not yet fixed with push_protected_branch
      # see https://github.com/github/authzd/issues/717
      return if action == :push_protected_branch
      if result.batch?
        batch_result = result
        batch_result.map.values.each do |res|
          dump = dump_attributes(batch_result.map.key(res).attributes)
          action = batch_result.map.key(res).attributes.detect { |attr| attr.id == "action" }.unwrapped_value
          next if "push_protected_branch" == action
          raise "Authzd returned INDETERMINATE for action \"#{action}\": an error happened while performing the authorization request: #{res.decision.reason} - do not rescue the exception and contact #authorization for support\n#{dump}" if res.indeterminate?
          raise "Authzd returned NOT_APPLICABLE for action \"#{action}\": the request did not match any policy - do not rescue the exception and contact #authorization for support\n#{dump}" if res.not_applicable?
        end
      else
        dump = dump_attributes(attributes)
        raise "Authzd returned INDETERMINATE for action \"#{action}\": an error happened while performing the authorization request: #{result.decision.reason} - do not rescue the exception and contact #authorization for support\n#{dump}" if result.indeterminate?
        raise "Authzd returned NOT_APPLICABLE for action \"#{action}\": the request did not match any policy - do not rescue the exception and contact #authorization for support\n#{dump}" if result.not_applicable?
      end
    end

    def self.dump_attributes(attributes)
      hash = Hash.new
      attributes.each do |attr|
        hash[attr.id] = attr.value.to_s
      end
      hash.to_yaml
    end

    def get_cached_requests(authzd_reqs)
      batch_result = nil
      cached_results = {}
      return [authzd_reqs, cached_results, batch_result] if authzd_reqs.empty?

      uncached_authzd_requests = authzd_reqs.reduce([]) do |memo, authzd_req|
        cache_key = Enforcer.cache_key(authzd_request: authzd_req)
        cached = PermissionCache.get(cache_key) unless cache_key.nil? # check if key is cached

        if !cached
          memo << authzd_req # add to request list
        else
          # add to result list
          cached_results[authzd_req] = cached
        end

        memo
      end

      if uncached_authzd_requests.empty?
        # all cached, create a local authzd-like response
        batch_result = Authzd::BatchResponse.from_decision(Authzd::Proto::BatchRequest.new(requests: cached_results.keys), Authzd::Proto::BatchDecision.new(decisions: cached_results.values.map(&:decision)))
        GitHub.dogstats.increment("ability.cache", tags: ["result:hit", "namespace:authzd_batch"])
      else
        cache_status = cached_results.empty? ? "miss" : "partial"
        GitHub.dogstats.increment("ability.cache", tags: ["result:#{cache_status}", "namespace:authzd_batch"])
      end

      [uncached_authzd_requests, cached_results, batch_result]
    end

    def self.cache_key(authzd_request:)
      return if authzd_request.nil?
      attr_hash = authzd_request.attributes.map { |a| [a.id, a.unwrapped_value] }.to_h
      ["PERMISSION_ENFORCER", attr_hash]
    end

    def self.cache_result?(decision)
      # don't cache error responses
      decision && !decision.indeterminate? && !decision.not_applicable?
    end
  end
end
