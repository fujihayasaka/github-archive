# typed: false
# frozen_string_literal: true

module ViewModelHelper

  # Internal: Create a new instance of a view model class. Automatically
  # provides a `:current_user` attribute to the view model.
  #
  # view_model_class - A Class inheriting from ViewModel or a ViewModel
  #                    instance. If it's a class, a new instance will be
  #                    created. If it's an instance it'll be dup'd and updated
  #                    with additional attributes.
  # attributes       - A Hash of attributes for the ViewModel or nil.
  #
  # Returns a ViewModel subclass instance.
  def create_view_model(view_model_class, attributes = nil)
    attributes ||= {}
    attributes[:current_user] = current_user
    attributes[:user_session] = user_session

    view_model = if view_model_class.is_a? ViewModel
      view_model_class.dup.update attributes
    else
      view_model_class.new(**attributes)
    end

    if Rails.env.test?
      # This lets us assert on `assigns(:view)` in controller tests.
      @view = view_model
    end

    view_model
  end
end
