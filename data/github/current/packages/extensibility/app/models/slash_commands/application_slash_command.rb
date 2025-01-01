# typed: true
# frozen_string_literal: true

module SlashCommands
  class ApplicationSlashCommand
    extend ActiveModel::Naming

    include ActiveModel::Validations
    include SlashCommands::FormHelper

    class PageNotFound < StandardError; end

    class << self
      attr_accessor :all_triggers, :pages, :_allowed_surfaces, :_feature_flag, :_category
    end

    sig { returns(String) }
    def self.id
      Digest::SHA256.hexdigest(self.name.to_s)
    end

    sig { params(subclass: T.class_of(ApplicationSlashCommand)).void }
    def self.inherited(subclass)
      subclass.all_triggers = []
      subclass.pages = []
      subclass._allowed_surfaces = SlashCommands::SUPPORTED_SURFACES
      subclass._category = SlashCommands::DEFAULT_CATEGORY
    end

    sig { params(name: String, title: String, description: T.nilable(String)).void }
    def self.trigger_on(name:, title:, description: nil)
      all_triggers << SlashCommands::Trigger.new(command: self, name: name, title: title, description: description)
    end

    sig { params(name: Symbol).void }
    def self.category(name)
      self._category = name
    end

    sig { params(surfaces: Symbol).void }
    def self.allowed_surfaces(*surfaces)
      # validate surfaces are supported
      unsupported = surfaces.select { |surface| !SlashCommands.supported_surface?(surface) }
      if unsupported.present?
        path = Pathname(SlashCommands.method(:supported_surface?).source_location.first)
        raise ArgumentError, "Surface(s) #{unsupported.to_sentence} are not supported surface(s). " \
        "See the list of supported surfaces in #{path.relative_path_from(Rails.root)}"
      end

      self._allowed_surfaces = SlashCommands.expand_surfaces(surfaces)
    end

    sig { params(flag: T.nilable(Symbol)).void }
    def self.feature_flag(flag)
      self._feature_flag = flag
    end

    sig { params(context: SlashCommands::Context).returns(T::Array[SlashCommands::Trigger]) }
    def self.triggers(context)
      all_triggers
    end

    sig { params(method_name: T.nilable(Symbol), if: T.nilable(Symbol), breadcrumb: T.nilable(String), validations: T.nilable(T.proc.params(page: SlashCommands::Page).void), reload_suggestions: T.nilable(T::Boolean), block: T.nilable(T.proc.void)).returns(T::Array[SlashCommands::Page]) }
    def self.menu(method_name = nil, if: nil, breadcrumb: nil, validations: nil, reload_suggestions: nil, &block)
      page = Page.new(
        type: :menu,
        method_name: method_name,
        breadcrumb: breadcrumb,
        reload_suggestions: reload_suggestions,
        predicate_method: binding.local_variable_get(:if),
        &block
      )

      if validations
        with_options(on: page.name, &validations)
      end

      pages << page
    end

    sig { params(method_name: T.nilable(Symbol), if: T.nilable(Symbol), breadcrumb: T.nilable(String), validations: T.nilable(T.proc.params(page: SlashCommands::Page).void), reload_suggestions: T.nilable(T::Boolean), block: T.nilable(T.proc.void)).returns(T::Array[SlashCommands::Page]) }
    def self.fill(method_name = nil, if: nil, breadcrumb: nil, validations: nil, reload_suggestions: nil, &block)
      page = Page.new(
        type: :fill,
        method_name: method_name,
        breadcrumb: breadcrumb,
        reload_suggestions: reload_suggestions,
        predicate_method: binding.local_variable_get(:if),
        &block
      )

      if validations
        with_options(on: page.name, &validations)
      end

      pages << page
    end

    sig { params(method_name: T.nilable(Symbol), if: T.nilable(Symbol), breadcrumb: T.nilable(String), style: Symbol, validations: T.nilable(T.proc.params(page: SlashCommands::Page).void), reload_suggestions: T.nilable(T::Boolean), block: T.nilable(T.proc.void)).returns(T::Array[SlashCommands::Page]) }
    def self.form(method_name = nil, if: nil, breadcrumb: nil, style: :embedded, validations: nil, reload_suggestions: nil, &block)
      page = Page.new(
        type: :form,
        method_name: method_name,
        breadcrumb: breadcrumb,
        reload_suggestions: reload_suggestions,
        form_style: style,
        predicate_method: binding.local_variable_get(:if),
        &block
      )

      if validations
        with_options(on: page.name, &validations)
      end

      pages << page
    end

    sig { params(method_name: T.nilable(Symbol), if: T.nilable(Symbol), breadcrumb: T.nilable(String), validations: T.nilable(T.proc.params(page: SlashCommands::Page).void), reload_suggestions: T.nilable(T::Boolean), block: T.nilable(T.proc.void)).returns(T::Array[SlashCommands::Page]) }
    def self.perform_action(method_name = nil, if: nil, breadcrumb: nil, validations: nil, reload_suggestions: nil, &block)
      page = Page.new(
        type: :action,
        method_name: method_name,
        breadcrumb: breadcrumb,
        reload_suggestions: reload_suggestions,
        predicate_method: binding.local_variable_get(:if),
        &block
      )

      if validations
        with_options(on: page.name, &validations)
      end

      pages << page
    end

    sig { params(surface: Symbol).returns(T::Boolean) }
    def self.surface_enabled?(surface)
      _allowed_surfaces.include?(surface)
    end

    sig { params(user: User).returns(T::Boolean) }
    def self.feature_flag_enabled?(user)
      _feature_flag.nil? || GitHub.flipper[_feature_flag].enabled?(user)
    end

    sig { params(context: SlashCommands::Context).returns(T::Boolean) }
    def self.enabled?(context)
      surface_enabled?(context.surface) && feature_flag_enabled?(context.current_user)
    end

    sig { params(attr: String, options: T::Hash[T.untyped, T.untyped]).returns(String) }
    def self.human_attribute_name(attr, options = {})
      attr.to_s.humanize
    end

    sig { returns(T::Array[T.class_of(SlashCommands::ApplicationSlashCommand)]) }
    def self.lookup_ancestors
      [self]
    end

    sig { returns(SlashCommands::Context) }
    attr_reader :context

    sig { returns(Flash) }
    attr_reader :flash

    sig { returns(T.any(NilClass, String, ActiveSupport::SafeBuffer, ActiveSupport::HashWithIndifferentAccess, ApplicationComponent, ActionController::Parameters)) }
    attr_accessor :component

    sig { params(context: SlashCommands::Context).void }
    def initialize(context)
      @context = context
      @flash = T.let(Flash.new, Flash)
    end

    delegate :id, :pages, to: :class
    delegate :current_repository, :current_user, :data, :page_number, :trigger, to: :context

    sig { returns(SlashCommands::Page) }
    def page
      @page ||= T.let(find_page_that_applies, T.nilable(SlashCommands::Page))
    end

    sig { returns(SlashCommands::Page) }
    def find_page_that_applies
      loop do
        page = pages[(page_number - 1)]

        if page.nil?
          raise PageNotFound
        elsif page.applies?(self)
          return page
        else
          context.next_page!
        end
      end
    end

    sig { returns(T.nilable(Repository)) }
    def template_source_repository
      trigger&.command_source_repository || current_repository
    end

    sig { returns(T::Array[SlashCommands::Page]) }
    def previous_pages
      return [] if page_number == 1

      pages[0..(page_number - 2)].select do |page|
        page.applies?(self)
      end
    end

    sig { returns(T.any(NilClass, String, ActiveSupport::SafeBuffer, ActiveSupport::HashWithIndifferentAccess, ApplicationComponent, ActionController::Parameters)) }
    def process
      tags = ["page:#{page_number}"]
      tags << "trigger:#{trigger.name}" unless trigger.nil?
      tags << "class:#{self.class.name}" if self.class.name.present?

      GitHub.dogstats.time("slash_commands.process", tags: tags) do
        if !valid?
          context.previous_page!
        end

        @component = T.let(page.call(self), T.any(NilClass, String, ActiveSupport::SafeBuffer, ActiveSupport::HashWithIndifferentAccess, ApplicationComponent, ActionController::Parameters))
      end
    end

    sig { params(attr: T.any(Symbol, String)).returns(T.nilable(String)) }
    def read_attribute_for_validation(attr)
      data[attr]
    end

    sig { returns(T::Boolean) }
    def valid?
      validation_contexts = previous_pages.map(&:name).compact
      super(validation_contexts)
    end

    sig { returns(T.nilable(SlashCommands::FlashMessageComponent)) }
    def footer
      SlashCommands::FlashMessageComponent.new(flash) if flash.present?
    end

    sig { returns(T.nilable(String)) }
    def custom_event
      nil
    end

    # Show the slash command name followed by breadcrumbs for every page up to
    # and including the current page. Pages without breadcrumbs won't appear.
    sig { returns(T::Array[String]) }
    def breadcrumbs
      [
        trigger&.title,
        *previous_pages.map(&:breadcrumb),
        page.breadcrumb
      ].compact
    end

    sig { returns(Integer) }
    def next_page_number
      page_number + 1
    end

    sig { returns(T::Boolean) }
    def first_page?
      context.page_number == 1
    end

    sig { returns(T::Boolean) }
    def last_page?
      pages.length == context.page_number
    end
  end
end
