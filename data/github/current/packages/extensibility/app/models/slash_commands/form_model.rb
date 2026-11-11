# typed: true
# frozen_string_literal: true

# Provides model for use with form_with.
#
# When you have a hash of data and a namespace, you can use this class to
# instantiate an object that will work with form_with.
#
# ==== Example: using class
#
#    form_model = SlashCommands::FormModel.new(
#      name: "User",
#      attributes: { username: "monalisa" },
#    )
#    form_model.errors.add(:username, "already taken")
#
#    form_with(model: form_model, url: "/profile", method: :patch) do |f|
#      f.text_field(:username) # <input name="user[username]" value="monalisa">
#                              # <p class="note.error">Username already taken</p>
#    end
#
# ==== Example: using with UI.form
#
#    profile_form = UI.form(url: "/profile", method: :patch)
#      .with_model(
#        name: "User",
#        attributes: { username: "monalisa" }
#        errors: { username: ["already taken"] }
#      ).with_fields(UI.text_field(:username))
#
#    render(profile_form) # <input name="user[username]" value="monalisa">
#                         # <p class="note.error">Username already taken</p>
module SlashCommands
  class FormModel
    include ActiveModel::Model

    attr_reader :attributes, :errors, :name
    def initialize(name:, attributes: nil, errors: nil)
      @name = name
      @attributes = attributes || {}
      @errors = build_errors_from(errors)

      define_getters
    end

    def define_getters
      attributes.each do |key, value|
        if respond_to?(key)
          raise ArgumentError.new("Invalid attribute name: #{key.inspect} (method already exists)")
        else
          define_singleton_method(key) do
            value
          end
        end
      end
    end

    def model_name
      @_model_name ||= ActiveModel::Name.new(self, nil, name)
    end

    private

    def build_errors_from(object)
      case object
      when ActiveModel::Errors then object
      when Hash                then build_errors_from_hash(object)
      when nil                 then ActiveModel::Errors.new(self)
      else
        raise ArgumentError.new("Can't derive errors from #{object}")
      end
    end

    def build_errors_from_hash(hash)
      errors = ActiveModel::Errors.new(self)

      hash.each do |field, values|
        Array(values).each do |value|
          errors.add(field, value)
        end
      end

      errors
    end
  end
end
