# typed: true
# frozen_string_literal: true

class Api::Hub < Api::App
  extend Forwardable

  # Hacks Sinatra::Base.middleware so we don't get the EnforceMediaType or Cors
  # middleware that is completely useless for PSHB.
  def self.middleware
    @middlware ||= [].freeze
  end

  MODES = Set.new %w(subscribe unsubscribe)

  def hub_request
    @hub_request ||= HubRequest.new(params)
  end
  def_delegators :hub_request, :mode, :topic, :callback, :repository, :hook, :event, :scheme

  # http://pubsubhubbub.googlecode.com/svn/trunk/pubsubhubbub-core-0.3.html#rfc.section.6.1
  #
  # hub.verify and hub.verify_token are ignored since all requests require
  # authentication.  No PubSubHubbub verification is needed.
  #
  # Callbacks can be either normal URLs or GitHub URLs:
  #
  #   github://campfire?room=abc&password=def
  #
  # Topics are URI endpoints that identify a Repository + an Event:
  #
  #   https://github.com/technoweenie/faraday/events/push
  #
  post "/hub", operation_id: :deprecated do
    @route_owner = "@github/ecosystem-events"
    @documentation_url = "/rest/reference/repos#pubsubhubbub"

    deliver_error! 404 unless GitHub.flipper[:webhooks_hub_api_endpoint].enabled?
    reject_invalid_host! if hub_request.invalid_host?

    control_access :authenticated_user,
      resource: repository,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    deprecation_date = Time.new(2022, 11, 15)
    deprecated(
      deprecation_date: deprecation_date,
      sunset_date: deprecation_date + 2.years,
      info_url: "",
      alternate_path_url: "/repositories/{repository_id}/hooks",
    )

    reject_invalid_hub_parameter!("callback") if hub_request.invalid_callback?
    reject_invalid_hub_parameter!("mode") if hub_request.invalid_mode?
    reject_invalid_hub_parameter!("topic") if hub_request.invalid_topic?

    reject_invalid_event! if hub_request.invalid_event?

    reject_repository_not_found! if repository.nil? || !can_create_or_update_hook?

    reject_invalid_hub_parameter!("callback") if hook.nil?

    # Since tests for this endpoint expect authorization to happen in a specific order,
    # to and as a stopgap measure so this endpoint is not bypassing CAP, a second capp is added.
    # Please note the first call opts out CAP enforcement
    control_access :authenticated_user,
      challenge: true,
      resource: repository,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    if mode == "subscribe"
      if hook.name == "web"
        format = if topic =~ /\.json$/i || (
          request.accept.any? { |mime| mime.to_s =~ /json/i })
          "json"
        else
          "form"
        end
        hook.update_existing_config({ "content_type" => format })
      end

      if hook.name == "email"
        emails_have_moved
      end

      if hook.name != "web"
        services_are_deprecated
      end

      hook.active = true
      hook.add_events(event)

      if hook.new_record?
        hook.track_creator(current_user)
      end

      unless hook.save
        deliver_error! 422, errors: hook.errors
      end
    elsif !hook.new_record?
      hook.remove_events(event)
      if hook.events.blank?
        hook.destroy
      else
        if hook.name == "email"
          emails_have_moved
        end

        if hook.name != "web"
          services_are_deprecated
        end

        hook.save!
      end
    end

    deliver_empty(status: 204)
  end

  def can_create_or_update_hook?
    set_current_repo_for_access_control(repository)

    if hook.nil? || hook.new_record?
      access_allowed? :create_repo_hook, repo: repository, allow_integrations: false, allow_user_via_granular_actor: false
    else
      access_allowed? :update_repo_hook, repo: repository, allow_integrations: false, allow_user_via_granular_actor: false
    end
  end

  def reject_invalid_hub_parameter!(parameter)
    deliver_error! 422,
      message: "Invalid hub.#{parameter}: '#{send(parameter)}'",
      documentation_url: "/rest/reference/repos#pubsubhubbub"
  end

  def reject_invalid_host!
    deliver_error! 422,
      message: "Invalid hub.topic hostname or protocol.",
      documentation_url: "/rest/reference/repos#pubsubhubbub"
  end

  def reject_invalid_event!
    deliver_error! 422,
      message: "Invalid event: #{event.inspect}",
      documentation_url: "/rest/reference/repos#pubsubhubbub"
  end

  def reject_repository_not_found!
    deliver_error! 422,
      message: "No repository found for hub.topic: #{topic.inspect}",
      documentation_url: "/rest/reference/repos#pubsubhubbub"
  end

  def services_are_deprecated
    deliver_error! 410,
      message: "GitHub Services have been deprecated. For more information please visit #{GitHub.developer_help_url}/developers/overview/replacing-github-services",
      documentation_url: "/rest/reference/repos#callback-urls"
  end

  def emails_have_moved
    deliver_error! 422,
      message: <<~MSG
      The GitHub email service has been replaced by repository push notifications. Please see the blog post for details: #{GitHub.developer_help_url(skip_enterprise: true)}/changes/2018-04-25-github-services-deprecation
      MSG
  end

  class HubRequest
    include Scientist

    attr_reader :params

    def initialize(params)
      @params = params
    end

    def topic
      params["hub.topic"].try(:strip)
    end

    def callback
      params["hub.callback"].try(:strip)
    end

    def mode
      params["hub.mode"]
    end

    def secret
      params["hub.secret"]
    end

    def hook
      return @hook if defined?(@hook)
      return if repository.nil? || callback.blank?
      uri = URI.parse(callback)
      @hook = case uri.scheme
      when "github" then uri_to_github_hook
      when "http", "https" then uri_to_web_hook
      end
    rescue URI::InvalidURIError
    end

    def repository
      if !defined? @repository
        @repository = Repository.nwo(attributes_from_topic[:repository_nwo])
      end
      @repository
    end

    def event
      attributes_from_topic[:event]
    end

    def invalid_host?
      if GitHub.enterprise?
        host_pattern = /^(www\.)?github\.com$|#{Regexp.escape(GitHub.host_name)}/
      else
        host_pattern = /^(www\.)?github\.com$/
      end

      return if topic.blank?
      uri = URI.parse(topic)

      if GitHub.ssl?
        return uri.scheme != "https"
      end

      uri.host !~ host_pattern
    rescue URI::InvalidURIError
      true
    end

    def invalid_callback?
      callback.blank?
    end

    def invalid_mode?
      !MODES.include?(mode)
    end

    def invalid_topic?
      topic.blank?
    end

    def invalid_event?
      !Hook.valid_event_type?(event)
    end

    def scheme
      URI.parse(callback).scheme
    end

    private

    def uri_to_github_hook
      uri    = URI.parse(callback)
      if repository.repo_hook_associations_ff?
        hook = Hook.where(installation_target: repository).where(name: uri.host).first_or_initialize(name: uri.host)
        GitHub::PrefillAssociations.prefill_associations([hook], [:installation_target], available_records: [repository])
        params = Rack::Utils.parse_query(uri.query)
        hook.config = params if params.present?
        hook
      else
        hook = repository.all_hooks.where(name: uri.host).first_or_initialize(name: uri.host)
        params = Rack::Utils.parse_query(uri.query)
        hook.config = params if params.present?
        hook
      end
    end

    def uri_to_web_hook
      if repository.repo_hook_associations_ff?
        hook = Hook.where(installation_target: repository).where(name: "web").detect do |record|
          record.config["url"] == callback
        end
        hook ||= Hook.new(installation_target: repository, name: "web", config: { "url" => callback })
        GitHub::PrefillAssociations.prefill_associations([hook], [:installation_target], available_records: [repository])
        hook.partial_config = { secret: secret } if secret
        hook
      else
        hook = repository.hooks.where(name: "web").detect do |record|
          record.config["url"] == callback
        end
        hook ||= repository.hooks.build(name: "web", config: { "url" => callback })
        hook.partial_config = { secret: secret } if secret
        hook
      end
    end

    def attributes_from_topic
      return {} if topic.blank?
      uri = URI.parse(topic)
      components = T.must(uri.path).split "/"
      return {} if components[3] != "events"
      event = components[4]
      return {} if event.blank?
      event.sub! /\..*/, ""
      { repository_nwo: "#{components[1]}/#{components[2]}", event: event }
    end
  end
end
