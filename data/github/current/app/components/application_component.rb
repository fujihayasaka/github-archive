# typed: true
# frozen_string_literal: true

require "primer/classify"

# As we migrate to the stricter ViewComponent::Base, this class exists to
# allow us to have components that inherit from the old and new base classes
class ApplicationComponent < ViewComponent::Base
  include GitHub::ComponentFastRenderPatch
  include ApplicationHelper, ColorHelper, Primer::FetchOrFallbackHelper
  include ::TurboFormHelper
  include TagAttributeHelper
  include StaticAssetHelper
  include EmojiHelper

  include GitHub::Memoizer

  delegate :feature_enabled_globally_or_for_user?, to: :helpers
  delegate :csrf_hidden_input_for, :authenticity_token_for, to: :helpers
  delegate :cap_filter, to: :helpers
  delegate :cap_view_filter, to: :helpers
  delegate :current_repository, to: :helpers
  delegate :canonical_request, :return_to_path, to: :helpers
  delegate :stylesheet_bundle, to: :helpers
  delegate :javascript_bundle, to: :helpers
  delegate :render_react_partial, to: :helpers
  delegate :react_partial_replacement, to: :helpers

  def self.inherited(child)
    child.include UrlHelper unless child < UrlHelper
    child.include GitHub::RouteHelpers unless child < GitHub::RouteHelpers

    super
  end

  sig { returns T.nilable(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
  def csrf_tokens
    controller.csrf_tokens
  end

  def current_user
    helpers.current_user
  end

  sig { returns T.nilable(T::Hash[T.any(String, Symbol), T::Boolean]) }
  def client_feature_flags
    controller.client_feature_flags
  end

  # Deprecated - prefer current_copilot_user_v2
  sig { returns T.nilable(Copilot::User) }
  def current_copilot_user
    controller.current_copilot_user
  end

  sig { returns T.nilable(T.any(Copilot::Public::User, Copilot::User)) }
  def current_copilot_user_v2
    controller.current_copilot_user_v2
  end

  def current_organization
    helpers.current_organization
  end

  sig { params(feature_name: T.nilable(Symbol)).returns(T::Boolean) }
  def user_feature_enabled?(feature_name)
    helpers.user_feature_enabled?(feature_name)
  end

  def user_or_global_feature_enabled?(feature_name)
    helpers.user_or_global_feature_enabled?(feature_name)
  end

  def logged_in?
    helpers.logged_in?
  end

  def robot?
    helpers.robot?
  end

  def mobile?
    helpers.mobile?
  end

  def preview_features?
    current_user&.preview_features?
  end

  def output_postamble
    asset_bundle = AssetBundlesHelper.new

    # We have to return "" so that we don't try to merge nil and String.
    return "" unless asset_bundle.bundle_exists?("#{self.class.asset_bundle_name}.css")

    # Ensure we don't cache ViewComponents with style tag links to bundles,
    # as we aren't sure if this approach is safe to cache.
    GitHub::CacheLeakDetector.no_caching!

    stylesheet_bundle(self.class.asset_bundle_name)
  end

  def self.asset_bundle_name
    @_asset_bundle_name ||= File.basename(T.must(self.class.name).demodulize.underscore, ".rb")
  end

  def css_identifier
    @css_identifier ||= T.must(self.class.name).underscore.split("/").join("--")
  end

  def class_for(name)
    "vc-#{css_identifier}-#{name}"
  end

  def aria_label_date(date)
    if date.today?
      :aria_label_time_today
    elsif date.yesterday?
      :aria_label_time_yesterday
    elsif date.year == Time.zone.now.year
      :aria_label_time_month_day
    else
      :aria_label_time_month_day_year
    end
  end

  class CurrentRender < ActiveSupport::CurrentAttributes
    attribute :cache
  end

  module Rescuable
    extend T::Helpers
    extend ActiveSupport::Concern

    include Kernel
    requires_ancestor { ViewComponent::Base }

    QUERY_TAG = "fallback:ApplicationComponent::Rescuable"

    included do |base|
      base.class_attribute :rescue_handlers, default: {}
    end

    def render_in(*)
      GitHub::ResilienceMixin.tag_queries(QUERY_TAG) { super }
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      # Unwrap errors that ocurred during template rendering
      if e.is_a?(ActionView::Template::Error) && e.cause.present?
        e = e.cause
      end

      helper = ResilienceHelper::GracefulDegradationErrorHandler.new(e, allowed_errors: self.class.rescue_handlers.keys, excluded_errors: [])
      raise unless helper.degradable? # re-raise there's no handler for this type of error

      handler = self.class.rescue_handlers[helper.allowed_error_type]
      helper.send_metrics("ApplicationComponent::Rescuable", T.unsafe(self))

      if handler.is_a?(Proc)
        case handler.arity
        when 1
          self.instance_exec(e, &handler)
        else
          self.instance_exec(&handler)
        end
      else
        handler.new(self).render_in(self.view_context)
      end
    end

    module ClassMethods
      extend T::Helpers
      include Kernel

      def rescue_from_database_errors(with: nil, &block)
        rescue_from(*T.unsafe(GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST), with:, &block)
      end

      def rescue_from(*classes, with: nil, &block)
        T.unsafe(self).rescue_handlers ||= {}

        if !block_given? && with.nil?
          raise ArgumentError, "You must pass a component or block to rescue_from"
        end

        classes.each do |klass|
          handler = if block
            block
          elsif with == :nothing
            proc { "" }
          else
            with = T.let(with, T.nilable(T.any(String, Class)))

            proc do
              T.bind(self, ViewComponent::Base)

              # Support passing handlers as string values
              with = self.class.const_get(with) if with.is_a?(String)
              with.new(self).render_in(self.view_context)
            end
          end

          T.unsafe(self).rescue_handlers[klass] = handler
        end
      end
    end

    mixes_in_class_methods(ClassMethods)
  end

  module Cacheable
    extend T::Helpers
    extend ActiveSupport::Concern

    module CacheCall
      def call
        @__vc_cached_call ||= super
      end
    end

    included do
      prepend CacheCall
    end

    module ClassMethods
      extend T::Helpers
      requires_ancestor { Module }

      def with(*args, **kwargs, &block)
        key = [args, kwargs, block]

        CurrentRender.cache ||= {}
        CurrentRender.cache[name] ||= {}
        CurrentRender.cache[name][key] ||= self.new(*T.unsafe(args), **kwargs, &block)

        CurrentRender.cache[name][key].tap do
          GitHub.logger.info(
            "cached_component.render",
            {
              "gh.view_component.global.cache_key.count": CurrentRender.cache.size,
              "gh.view_component.name": name,
              "gh.view_component.cache_key.count": CurrentRender.cache[name].size,
            }
          )
        end
      end
    end

    mixes_in_class_methods(ClassMethods)
  end
end
