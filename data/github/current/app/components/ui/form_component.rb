# typed: true
# frozen_string_literal: true

module UI
  class FormComponent < ApplicationComponent
    delegate :errors, to: :model
    attr_accessor :url
    attr_reader :model, :fields, :actions, :method, :data, :primer_tag_attributes, :allow_method_names_outside_object

    def initialize(url: nil, model: false, fields: [], actions: [], method: nil, data: nil, allow_method_names_outside_object: nil, **primer_system_arguments)
      @primer_tag_attributes = Primer::Classify.call(**primer_system_arguments)
      @url = url
      @model = model
      @method = method
      @data = data
      @allow_method_names_outside_object = allow_method_names_outside_object
      @fields = Array(fields)
      @actions = Array(actions)
    end

    def with_actions(*actions)
      @actions = actions

      self
    end

    # Inject fields into the form.
    #
    # You can provide one or more elements to render. Accepts ViewComponent instances
    # or strings. If a string is provided and is not already `html_safe?`, it is escaped.
    #
    # Returns self and can be chained.
    #
    # ==== Examples
    #
    # with_fields("Some text", UI.text_field(:name))
    def with_fields(*fields)
      @fields = fields

      self
    end

    # Inject data and errors into your form or namespace the fields.
    #
    # When you have a hash of data and a namespace, you can use this class to
    # instantiate an object that will work with form_with.
    #
    # See SlashCommands::FormModel for more information.
    #
    # Returns self and can be chained.
    #
    # ==== Options
    # * <tt>:name</tt> - Adds namespace to fields in the form.
    # * <tt>:attributes</tt> - Provide a hash to inject values into form fields. Optional.
    # * <tt>:errors</tt> - Provide errors as ActiveModel::Errors or as a hash. Optional.
    #
    # ==== Example: build a form with existing data and errors
    #
    #    profile_form = UI.form(url: "/profile", method: :patch)
    #      .with_model(
    #        name: "User",
    #        attributes: { username: "monalisa" },
    #        errors: { username: ["already taken"] }
    #      ).with_fields(UI.text_field(:username))
    #
    #    render(profile_form) # <input name="user[username]" value="monalisa">
    #                         # <p class="note.error">Username already taken</p>
    def with_model(name:, attributes: {}, errors: nil)
      @model = SlashCommands::FormModel.new(
        name: name,
        attributes: attributes,
        errors: errors
      )

      self
    end

    def kwargs_for_form_with
      primer_tag_attributes.merge({
        data: data,
        method: method,
        model: model,
        url: url,
        allow_method_names_outside_object: allow_method_names_outside_object,
      })
    end

    # Injects form builder into form field components and then wraps the fields in a stack.
    def fields_for(form)
      inject_form(fields, form: form)

      SlashCommands::StackComponent.new(fields)
    end

    # Inject form into components
    def inject_form(components, form:)
      components.each do |component|
        component.form = form if component.respond_to?(:form=)

        if component.respond_to?(:components)
          inject_form(component.components, form: form)
        end
      end
    end

    private

    def renderable?(item)
      item.respond_to?(:render_in)
    end
  end
end
