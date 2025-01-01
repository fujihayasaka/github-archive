# typed: strict
# frozen_string_literal: true

class Growth::BannerComponent < ApplicationComponent
  sig { returns T.nilable(Business) }
  attr_reader :business

  sig { returns Symbol }
  attr_reader :dismissible

  sig { returns T.nilable(T::Hash[String, String]) }
  attr_reader :dismiss_data

  sig { returns T.nilable(String) }
  attr_reader :notice_name

  sig { returns T.nilable(T.any(String, Symbol)) }
  attr_reader :icon

  sig { returns T.nilable(Organization) }
  attr_reader :organization

  sig { returns Symbol }
  attr_reader :scheme

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  sig { returns T.nilable(User) }
  attr_reader :user

  DEFAULT_DISMISSIBLE = T.let(:none, Symbol)
  DISMISSIBLE_VALUES = T.let([:user, :organization, :business, :none].freeze, T::Array[Symbol])

  DEFAULT_SCHEME = T.let(:banner, Symbol)
  SCHEME_VALUES = T.let([:banner, :full_width].freeze, T::Array[Symbol])

  sig do
    params(
      dismissible: Symbol,
      dismiss_data: T.nilable(T::Hash[String, String]),
      icon: T.nilable(T.any(String, Symbol)),
      notice_name: T.nilable(String),
      user: T.nilable(User),
      organization: T.nilable(Organization),
      business: T.nilable(Business),
      scheme: Symbol,
      system_arguments: Primer::SystemArgumentsValue).void
  end
  def initialize(dismissible: DEFAULT_DISMISSIBLE, dismiss_data: nil, icon: nil, notice_name: nil, user: nil, organization: nil, business: nil, scheme: DEFAULT_SCHEME, **system_arguments)
    @dismissible = T.let(fetch_or_fallback(DISMISSIBLE_VALUES, dismissible, DEFAULT_DISMISSIBLE), Symbol)
    case @dismissible
    when :user
      raise ArgumentError, "user is required for per-user notice dismissal" if user.blank?
      raise ArgumentError, "notice_name is required. Add an entry to config/notices.yml and run `bin/tapioca dsl UserNotice`" if notice_name.blank?
      raise ArgumentError, "unregistered user notice: #{notice_name}" unless UserNotice.const_defined?("#{notice_name}_notice".upcase)
    when :organization
      raise ArgumentError, "user is required for per-user notice dismissal" if user.blank?
      raise ArgumentError, "organization is required for per-organization-per-user notice dismissal" if organization.blank?
      raise ArgumentError, "notice_name is required. Add an entry to User::NoticesDependency::ORGANIZATION_NOTICES" if notice_name.blank?
      raise ArgumentError, "unregistered organization notice: #{notice_name}" unless User::NoticesDependency::ORGANIZATION_NOTICES.value?(notice_name)
    when :business
      raise ArgumentError, "user is required for per-user notice dismissal" if user.blank?
      raise ArgumentError, "business is required for per-business-per-user notice dismissal" if business.blank?
      raise ArgumentError, "notice_name is required. Add an entry to User::NoticesDependency::BUSINESS_NOTICES" if notice_name.blank?
      raise ArgumentError, "unregistered business notice: #{notice_name}" unless User::NoticesDependency::BUSINESS_NOTICES.include?(notice_name)
    end
    @scheme = T.let(fetch_or_fallback(SCHEME_VALUES, scheme, DEFAULT_SCHEME), Symbol)
    @icon = icon
    @notice_name = notice_name
    @dismiss_data = dismiss_data
    @user = user
    @organization = organization
    @business = business
    @system_arguments = system_arguments
    @system_arguments[:position] = :relative unless @system_arguments.key?(:position)
    @system_arguments[:border] = true unless @system_arguments.key?(:border)
    @system_arguments[:border_radius] = 2 unless @system_arguments.key?(:border_radius)
    @system_arguments[:border_color] = :default unless @system_arguments.key?(:border_color)
    @system_arguments[:p] = 3 unless @system_arguments.key?(:p)
    if notice_name.present?
      @system_arguments[:test_selector] = "banner_#{notice_name}" unless @system_arguments.key?(:test_selector)
    end
    @system_arguments[:classes] = class_names("overflow-hidden", { "js-notice": @dismissible != :none }, @system_arguments[:classes])
  end

  sig { returns T::Boolean }
  def render?
    case @dismissible
    when :user
      return false unless @user.present?
      return false if @user.dismissed_notice?(@notice_name)
    when :organization
      return false unless @user.present?
      return false unless @organization.present?
      return false if @user.dismissed_organization_notice?(@notice_name, @organization)
    when :business
      return false unless @user.present?
      return false unless @business.present?
      return false if @user.dismissed_business_notice?(@notice_name, business_id: @business.id)
    end
    true
  end

  renders_one :title, lambda { |**system_arguments|
    arguments = system_arguments
    arguments[:tag] = :p unless arguments.key?(:tag)
    arguments[:mb] = 0 unless arguments.key?(:mb)
    arguments[:classes] = "h4" unless arguments.key?(:classes)
    Primer::BaseComponent.new(
      **arguments,
    )
  }

  renders_one :description, lambda { |**system_arguments|
    arguments = system_arguments
    arguments[:tag] = :p unless arguments.key?(:tag)
    arguments[:font_size] = 6 unless arguments.key?(:font_size)
    arguments[:color] = :muted unless arguments.key?(:color)
    arguments[:mb] = 0 unless arguments.key?(:mb)
    Primer::BaseComponent.new(
      **arguments
    )
  }

  renders_one :action, lambda { |**system_arguments|
    arguments = system_arguments
    arguments[:tag] = :div unless arguments.key?(:tag)
    Primer::BaseComponent.new(
      **arguments
    )
  }
end
