# typed: true
# frozen_string_literal: true

module Search

  # Filters take the collection of qualifiers parsed from a search phrase and
  # convert them into a concrete ES filter hash that can be applied to one or
  # more document fields. This is the superclass for all the filters. It
  # provides methods for dealing with the qualifier boolean collections. It
  # provides a basic ES term filter implementation.
  class Filter
    # special-function values used in filter construction
    ANY      = "any"
    WILDCARD = "*"
    NONE     = "none"

    # special-function keys used in filter construction
    EXISTS   = :exists
    NO       = :no
    MISSING  = :missing

    attr_reader :field

    attr_reader :qualifiers

    attr_reader :keys

    attr_reader :options

    # A filter will be marked as invalid if one of the qualifiers does not
    # conform to the expected values. By default all filters a valid, even the
    # blank filters.
    #
    # Returns `true` if the filter is valid.
    attr_reader :valid
    alias :valid? :valid

    # A human readable message explaining why the filter is invalid.
    attr_reader :invalid_reason

    # Create a new Filter instance using the given options.
    #
    # opts - The options Hash
    #   :field        - The document field name this filter operates on
    #   :qualifiers   - The Hash of qualifiers parsed from the search phrase
    #   :keys         - The Array of qualifier keys to use
    #
    def initialize(opts = {})
      @options = opts

      @qualifiers = opts.fetch(:qualifiers, nil)
      @field      = opts.fetch(:field, nil)
      @keys       = opts.fetch(:keys, nil)
      @keys = Array(@keys) unless @keys.nil?

      @valid = true
    end

    # Returns a filter Hash that can be used in the `must` portion of an ES
    # boolean filter.
    def must
      build(bool_collection.must)
    end

    # Returns a filter Hash that can be used in the `must_not` portion of an ES
    # boolean filter.
    def must_not
      build(bool_collection.must_not)
    end

    # Returns a filter Hash that can be used in the `should` portion of an ES
    # boolean filter.
    def should
      build(bool_collection.should)
    end

    # Returns `true` if all of the components (must, must_not, should) are
    # empty. Returns `false` if any one of the components contains data.
    def blank?
      bool_collection.blank?
    end

    # Internal: Build a filter Hash from the given set of values. A default
    # term filter implementation is provided. But it is up to subclasses to do
    # their own special work here to build the appropriate filter.
    #
    # values - The Array of values from which to build the filter
    #
    # Returns a filter Hash or nil.
    def build(values)
      return if values.blank?
      build_term_filter(field, values)
    end

    # Internal: A filter uses a boolean collection to keep accumulate and
    # transform values before finally using them in building the filter Hash.
    #
    # Returns this filter's BoolCollection.
    def bool_collection
      return @bool_collection if defined? @bool_collection
      @bool_collection = ::Search::ParsedQuery::BoolCollection.new field

      return @bool_collection if qualifiers.nil?

      ary = (keys.nil? || keys.empty?) ? Array(field) : keys
      ary.each do |key|
        next unless qualifiers.key? key
        @bool_collection.merge! qualifiers[key]
      end

      @bool_collection
    end

    # Internal: The values provided to the filter via the qualifiers are
    # sometimes not in the correct format and need a little tweaking. This
    # method transforms the values by applying the `block` to the boolean
    # collection. We then intersect the must_not values with the must and
    # should - this removes must_not values from the other two.
    #
    # Examples
    #
    #   filter.map_bool_collection { |value| value.to_s.downcase }
    #
    # Returns this filter's BoolCollection.
    def map_bool_collection(&block)
      bool_collection.uniq!
      bool_collection.map_all!(&block) unless block.nil?
      bool_collection.intersect!
    end

    # FIXME: I really want to pull the two methods below out into a
    # `FilterHelper` moudule. The module would contain all the basic "build
    # this specific type of ES filter hash" methods we would want to use.
    # Either mix in the module to your class or just call the methods directly
    # on the module - they would have no state.

    # Internal: Construct a term filter for the given field and value. If the
    # value is an Array, then a terms filter will be created instead; if this
    # is the case, then an optional :execution style can be specified for how
    # the terms are searched.
    #
    # See the documentation below for more details about the :execution options.
    #
    # https://www.elastic.co/guide/en/elasticsearch/reference/master/query-dsl-terms-query.html
    # https://www.elastic.co/guide/en/elasticsearch/reference/master/query-dsl-bool-query.html
    #
    # name  - The field name as a String or Symbol.
    # value - The term as a String or an Array of Strings.
    # opts  - The options Hash
    #   :execution - one of :plain, :bool, :and, :or
    #
    # If the field name is prefixed with a negative `-`, then a **not** filter
    # will be generated and returned.
    #
    # Examples
    #
    #   build_term_filter( :language, 'Ruby' )
    #   #=> { :term => { :language => 'Ruby' } }
    #
    #   build_term_filter( :language, ['Ruby', 'JavaScript', 'C'] )
    #   #=> { :terms => { :language => ['Ruby', 'JavaScript', 'C']}}
    #
    #   build_term_filter( :label, ['search', 'bug'], :execution => :and )
    #   #=> { :bool => { :must => [
    #         { :term => { :label => 'search' } },
    #         { :term => { :label => 'bug' } }
    #       ] } }
    #
    # Returns the filter Hash or nil if a filter could not be created.
    def build_term_filter(name, value, opts = {})
      return if value.blank? && value != false

      execution = opts.fetch(:execution, :plain)
      value = value.first if value.is_a?(Array) && value.length == 1

      if value.is_a? Array
        if execution == :and
          must_filters = value.map { |term| { term: { name => term } } }
          { bool: { must: must_filters } }
        else
          h = { terms: { name => value } }
          h
        end
      else
        { term: { name => value } }
      end
    end

    def build_exists_filter(name)
      {
        exists: {
          field: "#{name}"
        }
      }
    end

    # Internal: Convert the given filter into a **not** version of the filter.
    #
    # filter - A filter Hash
    #
    # Returns the **not** version of the filter Hash.
    def negate(filter)
      ::Search::Filter.negate filter
    end

    # Convert the given filter into a **not** version of the filter.
    #
    # filter - A filter Hash
    #
    # Returns the **not** version of the filter Hash.
    def self.negate(filter)
      return if filter.blank?
      { bool: { must_not: filter } }
    end

  end  # Filter
end  # Search
