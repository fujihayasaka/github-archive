# frozen_string_literal: true

# In Rails 3.2 this defaults to true, but in Rails 4 this
# is set to false. Setting it to ture ensures that when
# `as_json` is called on an Active Record object, the model
# name is returned with the JSON object
ActiveSupport.on_load(:active_record) do
  self.include_root_in_json = true
end
