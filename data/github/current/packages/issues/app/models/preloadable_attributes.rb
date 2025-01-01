# typed: true
# frozen_string_literal: true

# Provides an interface to explicitly define instance variables as "preloadable".
# That is one-time-writable from the outside ie from some data preloader class.
# This is to avoid blanket exposure of attr_writers on instance vars.
module PreloadableAttributes
  extend ActiveSupport::Concern

  class_methods do
    def attr_preloadable(*attrs)
      T.unsafe(self).define_method :preloadables do
        return @preloadables if defined? @preloadables
        @preloadables = attrs
      end
    end
  end

  included do
    T.unsafe(self).attr_preloadable
  end

  def preload_attr(attr, value)
    Kernel.raise "No preloadables defined for #{T.unsafe(self).class.name}" unless T.unsafe(self).preloadables.any?
    if T.unsafe(self).preloadables.include?(attr)
      as_i_var = "@#{attr}"
      Kernel.raise "Preloadable #{attr} already set" if T.unsafe(self).instance_variable_get(as_i_var)
      T.unsafe(self).instance_variable_set(as_i_var, value)
    else
      Kernel.raise "Attribute #{attr} not defined as preloadable for #{T.unsafe(self).class.name}"
    end
  end
end
