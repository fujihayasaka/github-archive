# typed: true
# frozen_string_literal: true

class Forks::SearchOptionsResolver
  extend T::Sig

  sig { returns(T::Array[Symbol]) }
  attr_reader :include

  sig { returns(String) }
  attr_reader :period

  sig { returns(Symbol) }
  attr_reader :sort_by

  sig { returns(Integer) }
  attr_reader :page

  attr_writer :persisted

  DEFAULTS = {
    include: [:active],
    period: "2y",
    sort_by: :stargazer_counts,
    page: 1,
  }.freeze

  # The filter component is essentially a checkbox list, so
  # as users add and drop filters, we need a nice interface
  # to simply express the atomic state change desired.
  # When overriding filters, the caller provides the inclusion
  # directive to indicate the atomic change in the context of the
  # option being rendered: `include_archived: true` if we want to
  # add "archived" to the list of filters. `include_archived: false`
  # if we want to make sure it's not included.  This class
  # handles the complexity of generating the correct list based on these
  # directives.
  INCLUSION_MATCHER = /include_(?<inclusion>\w+)/.freeze

  sig { params(options: T::Hash[Symbol, T.untyped]).void }
  def initialize(options = {})
    @include = T.let(valid_param(:include, options), T::Array[Symbol])
    @enabled_features = T.let(options.fetch(:enabled_features, []), T::Array[Symbol])
    @period = T.let(valid_param(:period, options), String)
    @sort_by = T.let(valid_param(:sort_by, options), Symbol)
    @page = T.let(valid_param(:page, options), Integer)
    @persisted = false
  end

  sig { params(include: T.nilable(T.any(T::Array[T.any(String, Symbol)], String))).returns(T::Array[Symbol]) }
  def normalized_include(include)
    return DEFAULTS[:include] if include.nil?

    if include.is_a?(String)
      include = include.split(",").compact
    end

    (include.map(&:to_sym).filter { |value| value.in?(Forks::Controls::FilterComponent.valid_options) }).sort
  end

  def valid_param(param, params)
    value = params[param]
    case param
    when :include
      return normalized_include(value)
    when :sort_by
      value = value&.to_sym
      return value if value.in?(Forks::Controls::SortComponent.valid_options)
    when :period
      value = "" if value.nil?
      option_is_valid = value.in?(Forks::Controls::PeriodComponent.valid_options)
      # When :forks_view_unbound_period feature flag is removed,
      # we don't need to separate the `present?` and the `blank?` checks, so can
      # simply return option_is_valid ? value : DEFAULTS[:period]
      return value if value.present? && option_is_valid
      return value if value.blank? && feature_enabled?(:unbound_period)
      return DEFAULTS[:period]
    when :page
      # ApplicationController already handles pages over the maximum value, but because
      # this is a PORO that can just be instantiated anywhere, we need to
      # clamp it here too, in case the default behavior ever changes,
      # to prevent undefined behavior.
      return value.to_i.clamp(1, GitHub.max_ui_pagination_page)
    end
    DEFAULTS[param]
  end

  def copy(overrides = {})
    overrides[:include] = process_include_overrides(overrides)
    args = to_query_args
    args.update(overrides)
    # Enabled features aren't part of query args,
    # beacuse we don't want users to know about any of
    # that, so we set this explicitly after parsing the user-facing args.
    args[:enabled_features] = @enabled_features unless args.include?(:enabled_features)

    self.class.new(
      **args
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_query_args
    to_options_args.merge(page:)
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_options_args
    {
      period:,
      include: include.join(","),
      sort_by:,
    }
  end

  sig { params(feature_name: Symbol).void }
  def enable_feature(feature_name)
    # idempotent if added more than once for some reason
    @enabled_features << feature_name unless feature_enabled?(feature_name)
  end

  sig { params(feature_name: Symbol).returns(T::Boolean) }
  def feature_enabled?(feature_name)
    @enabled_features.include?(feature_name)
  end

  def persisted?
    @persisted
  end

  def freeze
    @enabled_features.freeze
    super
  end

  sig { params(overrides: T::Hash[Symbol, T.untyped]).returns(T::Array[Symbol]) }
  def process_include_overrides(overrides = {})
    # If the include array is explicitly provided, use it.
    return normalized_include(overrides[:include]) if :include.in?(overrides)

    # Otherwise, we perform additive operations based on the include matchers.
    # Updates a copy of the current inclusion list with any include_foo directives
    # provided in the overrides.
    result = include.dup
    overrides.each do |key, value|
      inclusion = INCLUSION_MATCHER.match(key.to_s)&.named_captures&.fetch("inclusion")&.to_sym
      next unless inclusion

      if value
        result << inclusion
      else
        result.delete(inclusion)
      end
    end
    result.uniq.sort
  end
end
