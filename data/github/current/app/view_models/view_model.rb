# typed: false
# frozen_string_literal: true

# An optional superclass for view models. `ViewModel` provides a
# consistent hash-based attributes initializer and access to a few
# basic Rails view modules.
#
# Be careful about adding things to this class. We're not trying to
# make a comprehensive view model framework or anything.

class ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include Scientist

  class Helpers
    include ActionView::Helpers::DateHelper
    include ActionView::Helpers::NumberHelper
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::UrlHelper
    include ActionView::Helpers::OutputSafetyHelper

    include AvatarHelper, EscapeHelper
    include BlobHelper
    include DiffHelper
    include HovercardHelper
    include PullRequestsHelper
    include OcticonsHelper
    include RepositoriesHelper

    # ActionView::Helpers depend on the #output_buffer accessor defined in
    # ActionView::Context (included in ActionView::Base) for nested helper
    # invocations (e.g. using a #link_to helper in the block to a
    # #content_tag helper).
    attr_accessor :output_buffer

    def initialize(view)
      @view = view
    end

    def logged_in?
      @view.logged_in?
    end

    def current_user
      @view.current_user
    end
  end

  class URLs
    include UrlHelpers
    include UrlHelper
    include GitHub::RouteHelpers

    # Yes, this is disgusting. However, it's a necessary evil if we want to
    # encapsulate Rails routes in ViewModels, and the disgustingness itself is
    # encapsulated too. Please contact @jakeboxer or @jbarnette if you're
    # wondering who to yell at.
    protected_instance_methods.each do |method|
      public method if method.to_s =~ /_(path|url)$/
    end
  end

  # Public: Track each attr_reader added to ViewModel subclasses.
  def self.attr_reader(*names)
    attr_initializable *names
    super
  end

  def self.attr_initializable(*names)
    attr_initializables.concat names.map(&:to_sym) - [:attributes]
  end

  # Internal: An Array of hash initializable attributes on this class.
  def self.attr_initializables
    @attr_initializables ||= (superclass <= ViewModel ? superclass.attr_initializables.dup : [])
  end

  # Internal: The attributes used to initialize this instance.
  attr_reader :attributes

  # Internal: The current user. If the session isn't anonymous, this
  # attribute is automatically added by the `create_view_model` helper.
  attr_reader :current_user

  # Internal: The current user session. If the session isn't anonymous, this
  # attribute is automatically added by the `create_view_model` helper.
  attr_reader :user_session

  # Public: Create a new instance, optionally providing a `Hash` of
  # `attributes`. Any attributes with the same name as an
  # `attr_reader` will be set as instance variables.
  def initialize(attributes = nil)
    update attributes || {}
    after_initialize if respond_to? :after_initialize
  end

  # Internal: Is there an authenticated user logged in?
  #
  # Returns a Boolean
  def logged_in?
    !!current_user
  end

  # Internal: Is the current user feature flagged?
  #
  # Returns a Boolean
  def current_user_feature_enabled?(flag)
    return false unless logged_in?

    result = FeatureFlag.vexi.enabled(flag, current_user, default: false)
    raise result.error if result.error # preserve error handling behavior
    result.value
  end

  # Internal: Call various text and application helpers through this
  # object.
  def helpers
    # TODO: avatar-urls feature flag (self)
    @helpers ||= ViewModel::Helpers.new(self)
  end

  # Internal: Update this instance's attribute instance variables with
  # new values.
  #
  # attributes - A Symbol-keyed Hash of new attribute values.
  #
  # Returns self.
  def update(attributes)
    (@attributes ||= {}).merge! attributes

    (self.class.attr_initializables & attributes.keys).each do |name|
      instance_variable_set :"@#{name}", attributes[name]
    end

    self
  end

  # Internal: Call generated route and URL helpers through this
  # object.
  def urls
    @urls ||= ViewModel::URLs.new
  end

  def application_view_context
    @application_view_context ||= ApplicationController.new.view_context
  end

  def request
    nil
  end
end
