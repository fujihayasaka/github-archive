# frozen_string_literal: true

module Memoizable
  def memoize(key)
    if memoized?(key)
      instance_variable_get(var_for(key))
    else
      instance_variable_set(var_for(key), yield)
    end
  end

  def memoized?(key)
    instance_variable_defined?(var_for(key))
  end

  private

  def var_for(key)
    "@#{key}"
  end
end
