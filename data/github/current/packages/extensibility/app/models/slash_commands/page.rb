# typed: true
# frozen_string_literal: true

module SlashCommands
  class Page
    FORM_STYLES = [
      :dialog,
      :embedded,
      :modal,
    ]

    attr_reader :method_name, :block, :predicate_method, :breadcrumb, :form_style, :submit_form

    def initialize(type:, method_name: nil, predicate_method: nil, breadcrumb: nil, form_style: nil, reload_suggestions: nil, submit_form: nil, &block)
      @type = type
      @method_name = method_name
      @predicate_method = predicate_method
      @block = block
      @breadcrumb = breadcrumb
      @form_style = form_style
      @reload_suggestions = reload_suggestions
      @submit_form = submit_form

      if method_name.nil? && block.nil?
        raise ArgumentError, "Must provide a method or a block"
      end

      unless form_style.nil? || FORM_STYLES.include?(form_style)
        raise ArgumentError, "The form style #{form_style} is not supported. See SlashCommand::Page::FORM_STYLES"
      end
    end

    def ui?
      @type == :form || @type == :menu
    end

    def type
      return @type unless form_style.present?
      form_type = form_style.to_s + "_form"
      form_type.to_sym
    end

    def reloads_suggestions?
      !!@reload_suggestions
    end

    # TODO: How should we handle blocks, which have no name?
    def name
      method_name
    end

    def applies?(instance)
      predicate_method.nil? || instance.public_send(predicate_method)
    end

    def call(instance)
      if method_name
        instance.public_send(method_name)
      elsif block
        block.call(instance)
      else
        raise "No callable for page: #{self}"
      end
    end
  end
end
