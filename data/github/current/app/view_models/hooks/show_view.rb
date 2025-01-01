# typed: true
# frozen_string_literal: true

module Hooks
  class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    CONTENT_TYPES = {
      "application/json" => "json",
      "application/x-www-form-urlencoded" => "form",
    }

    ACTIVE_MESSAGE = "Last delivery was successful.".freeze
    ERROR_MESSAGE = "Last delivery was not successful.".freeze
    INACTIVE_MESSAGE = "This hook is inactive.".freeze
    MUTED_MESSAGE = "This hook has been denied access by an organization administrator.".freeze
    UNUSED_MESSAGE = "This hook has never been triggered.".freeze

    attr_reader :hook, :use_new_hooks_ui

    def status_message
      return MUTED_MESSAGE if muted?
      return INACTIVE_MESSAGE unless hook.active?

      case Hookshot::Delivery.status_code_to_label hook.last_status
      when :active
        ACTIVE_MESSAGE
      when :unused
        UNUSED_MESSAGE
      when :hookshot_error
        ERROR_MESSAGE + " An exception occurred."
      else
        ERROR_MESSAGE + " #{hook.last_status_message}."
      end
    end

    def status_class
      return "mute" if muted?
      return "inactive" unless hook.active?

      Hookshot::Delivery.status_code_to_class hook.last_status
    end

    def base_url
      url = hook.url
      url = "http://#{url}" unless url =~ %r{\Ahttps?://}
      uri = Addressable::URI.parse(url).normalize
      port = ":#{uri.port}" if uri.port
      "#{uri.scheme}://#{uri.host}#{port}#{uri.path}"
    rescue Addressable::URI::InvalidURIError
      "Could not parse URL"
    end

    def title
      webhook? ? base_url : hook.display_name
    end

    def oauth_application_name
      hook.oauth_application.name
    end

    def webhook?
      hook.webhook?
    end

    def hook_type
      "webhook"
    end

    def hook_active_status
      hook.active? ? "enabled" : "disabled"
    end

    def hook_type_title
      hook_type.pluralize.titleize
    end

    def hook_events
      @hook_events ||= Hook::EventRegistry.
        subscribable_by(hook: hook, user: current_user).
        sort_by(&:display_name)
    end

    def content_types
      CONTENT_TYPES
    end

    def content_type
      hook.content_type
    end

    def push_event_only
      hook && hook.events == ["push"]
    end

    def wildcard_event
      hook && hook.events.include?(Hook::WildcardEvent)
    end

    def custom_events
      !push_event_only && !wildcard_event
    end

    def human_name(item)
      item.humanize
    end

    def label_correction(field)
      field.to_s.humanize.sub(/Github/, "GitHub")
    end

    def events_sentence(events = hook.events)
      if events.include?(Hook::WildcardEvent)
        "all events"
      else
        events.to_sentence
      end
    end

    def muted?
      return @muted if defined?(@muted)

      @muted = Hooks::OauthApplicationPolicyView.new(hook: hook).violates_policy?
    end

    def hook_disabled?
      (hook.installation_target_type == "Repository") && hook.installation_target.disabled?
    end

    def hook_target
      return unless hook_disabled?
      hook.installation_target.class.name.humanize
    end

    def include_push_option?
      Hook::Event::PushEvent.supports_target?(hook.installation_target)
    end

    def managed_by_oauth_app?
      hook.oauth_application && !hook.editable_by?(current_user)
    end

    def selected_link
      :hooks
    end

    def hide_checkbox?(hook_event)
      return false unless hook_event == Hook::Event::PackageV2Event
      # allow the user to unsubscribe from event
      !hook.events.include?(hook_event.event_type)
    end
  end
end
