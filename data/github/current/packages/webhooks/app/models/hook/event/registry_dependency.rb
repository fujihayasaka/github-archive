# typed: true
# frozen_string_literal: true

class Hook::Event
  module RegistryDependency
    extend ActiveSupport::Concern

    DEFAULT_TARGETS = T.let([Repository, Organization, Integration].freeze, [T.class_of(Repository), T.class_of(Organization), T.class_of(Integration)])

    module ClassMethods
      include Kernel
      def eager_load_events!
        return if Rails.application.config.eager_load

        # Hooks are implemented in a reload and autoload unfriendly.
        # Ideally this should not be done, but is necessary for this class to work.
        event_paths = Dir.glob(Rails.root.join("app/models/hook/event/*_event.rb"))
        event_paths += Dir.glob(Rails.root.join("packages/*/app/models/hook/event/*_event.rb"))
        event_paths.each { |event_file| require event_file }
      end

      def inherited(subclass)
        Hook::EventRegistry.register(subclass)
        super
      end

      # Public: Derives the Hook::Event's event_type (e.g. push) from
      # the class name.
      #
      # Returns a String.
      def event_type
        klass = T.cast(self, Class)
        @event_type ||= T.must(klass.name).demodulize.sub(/Event\z/, "").underscore
      end

      # Public: Mark this Event as one that is not subscribable. Auto subscribed
      # events are delivered without the hook having to explicitly subscribe to
      # the event (e.g. PingEvent).
      #
      # Prevents the event from being listed in the UI.
      #
      # Returns nothing.
      def auto_subscribed
        @auto_subscribed = true
      end

      # Public: Does this event fire without the hook having to be explicitly subscribed.
      #
      # Returns a Boolean.
      def auto_subscribed?
        !!@auto_subscribed
      end

      def supported_targets
        @supported_targets ||= Set.new
      end
      attr_writer :supported_targets

      # Public: Specifies the Hook installation targets this Event supports.
      #
      # target_classes  - A list of Classes.
      #
      # Returns nothing
      def supports_targets(*target_classes)
        self.supported_targets += Array.wrap(target_classes)
      end

      # Public: Determines if the given target is supported by this Event.
      #
      # target - An class or instance to be checked.
      #
      # Returns a Boolean.
      def supports_target?(target)
        supported_targets.any? do |supported_class|
          target == supported_class ||
            target.instance_of?(supported_class)
        end
      end

      # Public: Sets or returns the Hook::Event's display name. This information
      # will be shown in the UI.
      #
      # name - (optional) The String display name.
      #
      # Returns the specified display name String.
      def display_name(name = nil)
        if name
          @display_name = name
        else
          @display_name || event_type.gsub("_", " ").pluralize
        end
      end

      # Public: Sets or returns the Hook::Event's description. This information
      # will be shown in the UI to help users understand the event's purpose.
      #
      # description - (optional) The String description.
      #
      # Returns the specified description String.
      def description(desc = nil)
        if desc
          @description = desc
        else
          @description
        end
      end

      # Public: Determines whether the event is visible given a user and
      # a webhook installation target (repo, org, etc.).
      # This implementation only checks if the feature flag is enabled for the user,
      # but event classes can override this as needed.
      # Events that override this method should gracefully handle the
      # case where user and target are nil.
      #
      # user - A User object, most likely current_user.
      # target - The hook installation target, most likely the current target.
      #
      # Returns a boolean
      def visible_for?(user, target)
        if feature_flagged?
          if flagged_actions.present?
            true
          else
            feature_flag_enabled_for(user)
          end
        else
          true
        end
      end

      # Public: Sets or returns the Hook::Event's feature flag. Useful for creating
      # new events that will only be shown to certain users. Feature flagged events
      # will not automatically fire for hooks which subscribe to all events.
      #
      # flag - (optional) The Flipper feature name (e.g. :preview_hook_events)
      # actions - (optional) The list of actions to check against the feature flag
      # ui_note - (optional) When true, will render a lock and special message in webhook form ui
      #                      to indicate the event is not public.
      # block - (optional) When a block is given, it will get executed instead of
      #                    checking Flipper.
      #
      # Returns the specified flag Symbol.
      def feature_flag(flag = nil, actions: [], ui_note: true, &flag_block)
        if flag
          @flag_proc = flag_block
          @flagged_actions = actions
          @ui_note = ui_note
          @flag = flag.to_sym
        else
          @flag
        end
      end

      # Public: Returns whether or not the actor has the feature flag enabled.
      # When there is a feature flag block, it will call it to delegate the check.
      #
      # Returns a Boolean.
      def feature_flag_enabled_for(actor)
        if @flag_proc
          @flag_proc.call(@flag, actor)
        else
          FeatureFlag.vexi.enabled?(@flag, actor, default: false)
        end
      end

      # Public: Returns whether or not a feature flag has been specified for this
      # Hook::Event.
      #
      # Returns a Boolean.
      def feature_flagged?
        feature_flag.present?
      end

      # Public: Returns any flagged actions for this Hook::Event.
      #
      # Returns an Array.
      def flagged_actions
        @flagged_actions
      end

      # Public: Whether or not to render lock and UI note for this event
      def feature_flag_ui_note?
        feature_flagged? && flagged_actions.blank? && !!@ui_note
      end
    end
  end
end
