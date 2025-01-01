# typed: strict
# frozen_string_literal: true

class MemberFeatureRequest::Notification::Setting
  extend T::Sig

  sig { returns(T::Boolean) }
  attr_reader :all

  sig { returns(T::Boolean) }
  attr_reader :ignore

  sig { returns(T::Boolean) }
  attr_reader :user_enabled

  sig { returns(String) }
  attr_reader :trigger

  sig { returns(T::Array[String]) }
  attr_reader :features

  sig { params(all: T::Boolean, ignore: T::Boolean, user_enabled: T::Boolean, trigger: String, features: T::Array[String]).void }
  def initialize(all: false, ignore: false, user_enabled: false, trigger: "any", features: [])
    @all = all
    @ignore = ignore
    @user_enabled = user_enabled
    @trigger = trigger
    @features = features
  end

  sig { void }
  def all!
    @all = true
    @trigger = "any"
    @user_enabled = true
  end

  sig { void }
  def ignore!
    @ignore = true
    @trigger = "any"
    @user_enabled = false
  end

  sig { params(features: T::Array[String]).void }
  def custom!(features:)
    return ignore! if  MemberFeatureRequest::Feature.values.map(&:to_s).all? { |feature| features.include?(feature) }

    @ignore = false
    @all = false
    @trigger = "custom"
    @user_enabled = false

    @features = features
  end

  sig { returns(T::Boolean) }
  def all?
    all
  end

  sig { returns(T::Boolean) }
  def custom?
    @features.any?
  end
end
