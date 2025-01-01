# typed: true
# frozen_string_literal: true

module CopilotAPI
  class AccessControl < Platform::Authorization::Permission
    include GitHub::Memoizer

    attr_reader :env

    def initialize(context)
      @token = context.fetch(:token)
      # this also happens in the superclass initializer,
      # but we need it in the `authentication` method which might get called via `user``
      # before we call super
      @remote_ip = context[:ip]
      context[:origin] = Platform::ORIGIN_API
      context[:viewer] = user unless context.key?(:viewer)
      @env = {}
      super
    end

    sig { returns GitHub::Authentication::Result }
    def authentication
      @authentication ||= GitHub::Authentication::Attempt.new(
        token:                              token,
        ip:                                 @remote_ip,
        from:                               :copilot_api,
        allow_integrations:                 false,
        allow_user_via_granular_actor:      true,
        password_auth_blocked:              true
      ).result
    end

    def user
      authentication.user
    end

    # subclass the access_allowed method solely so we can log its result
    def access_allowed?(action, options = {})
      result = super
      logged_options = options.transform_values do |v|
        if v.is_a?(User)
          klass_name = v.organization? ? "Organization" : "User"
          # we want tenant suffixes for both orgs and users if they are present
          { type: klass_name, login: v.login, id: v.id } # rubocop:disable GitHub/DoNotAllowLogin
        elsif v.is_a?(Repository)
          { type: "Repository", nwo: v.name_with_owner, id: v.id } # # rubocop:disable GitHub/DoNotAllowNameWithOwner
        elsif v.respond_to?(:id)
          { type: v.class.name, id: v.id }
        else
          v
        end
      end
      # This flag will only be enabled for one or two users at a time, and only as part of
      # investigating https://github.com/github/copilot-experiences/issues/6826
      always_log = @authentication&.user.present? && FeatureFlag.vexi.enabled?(:copilot_spaces_control_access_logging, @authentication&.user, default: false)

      if always_log || (!result && FeatureFlag.vexi.enabled?(:copilot_api_twirp_control_access_decision_logging, default: false))
        GitHub.logger.info("CopilotApi::AccessControl result",
          "gh.copilotapi.access_control.access_allowed": result,
          "gh.copilotapi.access_control.token": token,
          "request_id": GitHub.context[:request_id],
          "gh.copilotapi.control_access.options": logged_options.to_json,
          # @remote_ip is set from context[:ip] in the parent class initializer
          "gh.copilotapi.control_access.ip": @remote_ip,
          "gh.copilotapi.control_access.action": action,
          # this is the viewer_id from the context
          "gh.copilotapi.control_access.viewer_id": @viewer_id,
          # check the instance variable directly because if we set @authentication after initializing
          # CopilotAPI::AccessControl, we'll violate the `freeze` set by the parent Platform::Authorization::Permission
          # class
          "gh.copilotapi.control_access.token_user_id": @authentication&.user&.id,
          "gh.copilotapi.control_access.token_failure_reason": @authentication&.failure_reason,
          )
      end
      result
    end

    private

    attr_reader :token
  end
end
