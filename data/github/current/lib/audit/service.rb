# typed: true
# frozen_string_literal: true

module Audit
  class Service
    # Error raised when a logged event could have leaked staff identities
    class StaffIdentityLeakError < ArgumentError; end

    autoload :PreparedData, "audit/service/prepared_data"

    attr_reader :logger, :searcher
    attr_accessor :statsd

    DEFAULT_ON_ERROR = lambda { |_err| }

    # The Audit::Service is the external entry point for logging and searching
    # audit entries.  Typically, an application-wide instance will be set to
    # GitHub.audit.

    #   # Log an event to background job => Elastic Search
    #   GitHub.audit.log('signup') { {:current_user => current_user.id} }
    #
    #   # Query elastic search
    #   GitHub.audit.search(:current_user => current_user.id)
    #
    # The two main operations of the service (logging and searching) are
    # delegated to separate objects to mix and match your auditing strategy.
    # For example, you may wish to queue your audit logs for a periodic bulk
    # insert, while querying directly against ElasticSearch.
    #
    # options - Hash to configure the service.  If no options are passed, the
    #           service's methods are basically no-ops.
    #           :logger - The Audit Logger instance. See Audit::Elastic::Logger
    #                     for the expected interface.
    #           :search - The Audit Searcher instance. See
    #                     Audit::Elastic::Searcher for the expected interface.
    #           :statsd - Optional StatsD::Client
    #
    def initialize(options = {})
      @logger   = options[:logger]
      @searcher = options[:searcher]
      @statsd   = options[:stats] || options[:statsd] || GitHub::NullStatsD.new
      @on_error = DEFAULT_ON_ERROR
    end

    # Public: Logs the given data to the Logger instance.
    #
    # You can either pass data directly to #log, or yield it.  The benefit of
    # yielding is that the block is not called if there is no logger set.
    #
    #     # no logger set, so it's a no-op
    #     GitHub.audit = Audit::Service.new
    #
    #     # Early return!
    #     GitHub.audit.log('foo') { HolyCrap.building_hashes_is_hard }
    #
    # action - A String key identifying the action..
    # data   - The Hash of data that is sent over as JSON.
    #          :actor    - The User that is performing the action.
    #          :actor_ip - The String IP address of the actor.
    #          :user     - The User that is the subject of the action.
    #          :repo     - The Repository that is the subject of the action.
    #          :from     - A String identifying the controller action or class
    #                      that triggered this:  "users_controller#create" or
    #                      "GitHub::Jobs::FooJob"
    #          :note     - String description of the action.
    #          :sha      - String Commit SHA of the Repository (for things like
    #                      force pushes or branch deletions).
    #
    # Returns true if the log succeeded.
    def log(action, data = nil)
      return if !@logger
      data ||= yield if block_given?
      return if data.blank?
      payload = build_payload(action, data)
      ensure_staff_action_privacy(action, payload)
      log_payload(action: action, payload: payload)
    end

    # Public: Normalizes location data to match that of the audit log
    #
    # location - The location hash to normalize
    def normalize_location(location)
      return if location.nil? || location[:location].present?
      location[:location] = {
        lat: location.delete(:latitude).to_f,
        lon: location.delete(:longitude).to_f,
      }
    end

    def action_from_stafftools?(payload)
      return true if GitHub.guard_console_staff_actor?
      # It turns out `from` is an overloaded payload key. Sometimes it is a
      # String and sometimes it is a Symbol, so we call `to_s` on it to handle
      # both cases.
      from = payload[:from].to_s
      user_agent = payload[:user_agent].to_s
      job = payload[:job].to_s
      from.include?("stafftools") || from.include?("biztools") || from.include?("devtools") || (
        (
          # Since user_agent can be manipulated by the client, we need to ensure
          # that we guard the actor only if they are a staff member
          user_agent == "spamurai-next-graphql" ||

          ## These places log the github-staff actor in the actor field
          job == "ExpireBusinessAdminInvitationsJob" ||
          from == "businesses/owner_invitations#update"
        ) && actor_is_staff?(payload)
      )
    end

    # Ensures that logged actions are not inadvertantly releasing identity
    # information of staff for staff actions
    #
    # Raises StaffIdentityLeakError if leaking
    def ensure_staff_action_privacy(action, payload)
      if staff_action?(action) && unsafe_staff_actor?(payload)
        raise StaffIdentityLeakError, "Staff audit log event #{action} uses actor without staff_actor"
      end
    end

    # Checks if an action is in the staff namespace
    def staff_action?(action)
      action.starts_with?("staff.")
    end

    # Checks if the actor in a payload is the github staff user
    def unsafe_staff_actor?(payload)
      return false unless GitHub.guard_audit_log_staff_actor?
      payload[:actor] != GitHub.staff_user_login
    end

    # Moves the actor into the staff_actor and sets the actor to be the staff user
    def set_staff_actor(payload)
      return payload unless GitHub.guard_audit_log_staff_actor?

      if payload[:actor] != GitHub.staff_user_login
        payload[:staff_actor] = GitHub.guard_console_staff_actor[:actor] || payload[:actor]
        payload[:staff_actor_id] = GitHub.guard_console_staff_actor[:actor_id] || payload[:actor_id]
        payload[:actor] = GitHub.staff_user_login
        payload[:actor_id] = User.staff_user.id
      end
      payload
    end

    # If actions are being reported from an impersonated session,
    # update the actor so that log entries accurately represent
    # the actions being taken on behalf of the user
    def set_impersonated_actor(payload)
      return payload unless payload[:session_impersonated].present?

      payload.merge({ user_id: payload[:actor_id] }) if payload[:user_id].blank?
      # If reporting for GitHub.enterprise, show the admin as the impersonator
      # otherwise, show GitHub.staff_user as the impersonator
      if GitHub.guard_audit_log_staff_actor?
        payload[:actor] = GitHub.staff_user_login
        payload[:actor_id] = User.staff_user.id
      else
        actor = User.find_by_login(payload[:session_impersonated_by])
        payload[:actor] = actor.login
        payload[:actor_id] = actor.id
      end
      payload.except!(:session_impersonated_by)
    end

    # Public: Searches for Audit records.  See the Searcher#perform for
    # specifics according to the backing search store.
    #
    #     items = GitHub.audit.search(:actor_id => current_user.id)
    #     items.each do |entry|
    #       puts entry.inspect
    #     end
    #
    # query - A Hash of required filters.
    #
    # Returns an Array of found audit Hashes.
    def search(query)
      return if !@searcher
      @searcher.perform(query)
    rescue StandardError => err # rubocop:todo Lint/GenericRescue
      @on_error.call err
      Search::Results.empty
    end

    # Public: Lets you set an on-error callback for when #log and #search fail.
    # Don't interrupt the app, but do log the error somewhere.
    #
    #     GitHub.audit.on_error do |exception|
    #       puts exception
    #       puts exception.stacktrace.join("\n")
    #     end
    #
    # Returns the new on-error callback Block.
    def on_error(&block)
      @on_error = block || DEFAULT_ON_ERROR
    end

    # Internal: Builds a payload Hash full of ActiveRecord models into a Hash
    # that can easily be serialized to JSON for the Audit logging service.
    #
    # action  - A String action, passed to #log.
    # data    - The Hash of data passed to #log.
    #
    # Returns the finished Hash payload.
    def build_payload(action, data)
      payload = Audit.context.to_hash.symbolize_keys
      payload = payload.merge(data.symbolize_keys, { action: action })
      payload = expand_payload(payload)
      payload = set_staff_actor(payload) if action_from_stafftools?(payload)
      payload = set_impersonated_actor(payload) if payload[:session_impersonated].present?
      payload
    end

    # Internal: Expands payload with additional information we want on all audit events
    def expand_payload(payload)
      ::Audit::Service::PreparedData.build(input: payload, discard_timestamp: true).output
    end

    # Internal: Logs a payload without building it first (assume it's ready to
    # be logged).
    # Caution! This method may produce malformed records in the Audit Log
    # if passed an unknown action or a payload that has not yet been modified
    # using #build_payload.
    #
    # action            - A String action, passed to #log.
    # payload           - A full Hash, already passed through #build_payload.
    # on_error_behavior - A block or the symbol :raise. If passed :raise,
    #                     errors will be immmediately raised. If passed a block
    #                     it will be called overriding the Audit::Service#on_error block.
    #
    # Returns true if the operation succeeds, otherwise false.
    def log_payload(action:, payload:, on_error_behavior: nil)
      GitHub.dogstats.distribution("audit.service.log_payload.payload_size", payload.to_json.bytesize)
      @statsd.increment "#{cluster_stat_prefix}.names.#{action.gsub('.', '-')}"
      @statsd.time "#{cluster_stat_prefix}.log" do
        @logger.perform(payload)
      end

      true
    rescue StandardError => err # rubocop:todo Lint/GenericRescue
      if on_error_behavior == :raise
        raise err
      elsif on_error_behavior.respond_to?(:call)
        on_error_behavior.call(err)
      else
        @on_error.call(err)
      end

      false
    end

    # This method is a noop when called directly on this class. Delegates
    # and sub-classes change this behavior.
    def inline
      yield
    end

    # Delegates and sub-classes change this behavior, by default it's always
    # true (inlining on) when this class is used directly.
    def inline?
      true
    end

    private

    def actor_is_staff?(data)
      return false unless GitHub.guard_audit_log_staff_actor?
      actor = User.find_by(id: data[:actor_id])
      return false unless actor
      actor.site_admin? || actor.employee?
    end

    def cluster_stat_prefix
      # Certain loggers don't support selecting the cluster.
      # TODO: Move logging and searching to their respective classes.
      if logger.respond_to?(:cluster) && logger.cluster.present?
        "audit.cluster.#{logger.cluster}"
      else
        "audit"
      end
    end
  end
end
