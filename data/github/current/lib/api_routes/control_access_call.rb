# typed: true
# frozen_string_literal: true

class ApiRoutes::ControlAccessCall
  attr_reader :name, :controls
  def initialize(name)
    @name = name
    @enabled = false
    @controls = {}
  end

  def verb
    name
  end

  def set(key, value)
    @controls[key] = value
  end

  def enabled!
    @enabled = true
  end

  def enabled?
    @enabled
  end

  def s2s?
    !!controls[:allow_integrations]
  end

  def u2s?
    !!controls[:allow_user_via_granular_actor]
  end

  def audited?
    !(controls[:allow_integrations].nil? || controls[:allow_user_via_granular_actor].nil?)
  end
end
