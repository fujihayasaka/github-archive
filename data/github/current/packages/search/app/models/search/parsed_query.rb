# typed: true
# frozen_string_literal: true

require "strscan"

module Search

  class ParsedQuery
    # Used to configure how deep to go for recursive macro replacement within arrays.
    MAX_RECURSION_DEPTH = 5

    private_constant :MAX_RECURSION_DEPTH

    # Public: Parse search query syntax.
    #
    # Parsing preserves query text and term ordering so the original query
    # string can be reconstructed from the parsed structure.
    #
    # There are a few exceptions.
    #
    # 1. Whitespace is normalized. Extra and multiple whitespace characters will
    #    be stripped.
    # 2. Quoting is normalized by default. Term values with unneeded quotes will be
    #    stripped. Pass `normalize_quotes: false` to preserve quotes.
    # 3. Legacy @user and @user/repo syntax is normalized to user: and repo:
    #    terms.
    #
    # str   - The String query
    # terms - Array of qualifier term Symbols. They can use regex-syntax like "props\\.\\w+"
    # enumerable_terms - Terms that get parsed using a memex-style syntax,
    # where term_name:foo,bar becomes [:term_name, ["foo", "bar"]] instead of
    # [:term_name, "foo,bar"]. They can use regex-syntax like "props\\.\\w+"
    # viewer - The viewer of the search query. You'll usually pass current_user if you override this.
    # replace_me - Whether to replace @me with the viewer's login.
    # replace_today - Whether to replace @today with the current date.
    # escape_terms - Whether to escape terms. Useful when passing regular expressions as parts of terms.
    # normalize_quotes - Whether to normalize quotes.
    #
    # Examples
    #
    #     parse("parser label:search author:TwP", terms: [:label, :author])
    #     # => ["parser", [:label, "search"], [:author, "TwP"]]
    #
    # Returns an Array of components, where a component is a literal String
    # query or a Array of [Symbol key, String|Array value, Boolean negative].
    def self.parse(
      str,
      terms: [],
      enumerable_terms: [],
      viewer: nil,
      replace_me: false,
      replace_today: false,
      escape_terms: false,
      normalize_quotes: true
    )
      str = str.to_s.encode(Encoding::UTF_8, invalid: :replace)
      str = str.strip.scrub!
      scanner = StringScanner.new(str)

      # We cannot always assume we want to escape terms because some sub-classes have been implemented with the
      # assumption/need to pass in regular expression parts (for example: RepoQuery#PROPERTIES_PREFIXED_REGEX_TEXT
      # will be passed in.)  Some parts of our codebase will pass in more user-controlled data into terms (such as
      # column names for Project item filtering) and do require properly escaping terms.
      accepted_regex_terms = escape_terms ? Regexp.union(terms.map(&:to_s)) : terms.join("|")

      term_start_rgxp = /(?:^|\s)(-?)(#{accepted_regex_terms}):/ if terms.any?
      quoted_value_rgxp = /("(?:(?<=\\)"|[^"])*")/
      unquoted_value_rgxp = /([^, ]+)/
      ary = []
      query = ""

      enumerable_terms_rgxp = if enumerable_terms.any?
        escaped_enumerable_terms = escape_terms ? Regexp.union(enumerable_terms.map(&:to_s)) : enumerable_terms.join("|")
        /^(#{escaped_enumerable_terms})$/
      end

      until scanner.eos?
        # look for qualifier terms in the search phrase
        if term_start_rgxp && scanner.scan(term_start_rgxp)
          ary << query.strip unless query.blank?
          query = ""

          key = scanner[2].to_sym
          is_negative = scanner[1].present?
          components = []
          values_left = T.let(true, T::Boolean)
          while values_left
            if scanner.scan(quoted_value_rgxp)
              component = if normalize_quotes
                # remove the first and last character as they're the quotes
                scanner[1].delete_prefix('"').delete_suffix('"').gsub('\\"', '"')
              else
                scanner[1]
              end

              components << component
            elsif scanner.scan(unquoted_value_rgxp)
              components << scanner[1]
            end

            values_left = false unless scanner.scan(",")
          end

          is_enumerable_term = enumerable_terms_rgxp && key.match(enumerable_terms_rgxp)

          # We explicitly opt in to using the "or" syntax to prevent changing
          # the old behavior too much. For example, if we're parsing the `label` field:
          # if the field is enabled, label:foo,bar will become [:label, ["foo", "bar"]]
          # if not enabled  it'll be parsed as [:label, "foo,bar"]
          value = if components.length > 1 && is_enumerable_term
            # Instrument the search so we can see how many times users with the flag enabled are using the `label:foo,bar`
            # syntax.  We tag the number of components -- label:foo,bar would be tagged as `count:2`
            stats_count = components.length < 10 ? components.length.to_s : "10+"
            GitHub.dogstats.increment("issues.enum_syntax.search", tags: ["count:#{stats_count}"])
            components
          else
            components.join(",")
          end

          value = apply_me_macro(viewer, :user, value) if replace_me && viewer
          value = apply_today_macro(value, viewer) if replace_today

          if is_negative
            ary << [key, value, true]
          else
            ary << [key, value]
          end

        # look for escaped characters
        elsif scanner.scan(/\\/)
          query += scanner[0]
          query += (scanner.getch || "") unless scanner.eos?

        # look for @user/repo
        elsif terms.include?(:repo) && scanner.scan(/(?:^|\s)(-?)@([\w\-]+\/[\w\-.]+)(?=\s|$)/)
          ary << query.strip unless query.blank?
          query = ""

          value = scanner[2]
          if scanner[1].blank?
            ary << [:repo, value]
          else
            ary << [:repo, value, true]
          end

        # look for @user
        elsif terms.include?(:user) && scanner.scan(/(?:^|\s)(-?)@([\w\-]+)(?=\s|$)/)
          ary << query.strip unless query.blank?
          query = ""

          value = scanner[2]
          value = apply_me_macro(viewer, :user, value) if replace_me && viewer

          if scanner[1].blank?
            ary << [:user, value]
          else
            ary << [:user, value, true]
          end

        # look for #topic
        elsif terms.include?(:topic) && scanner.scan(/(?:^|\s)(-?)#([\w\-]+)/)
          ary << query.strip unless query.blank?
          query = ""

          value = scanner[2]
          if scanner[1].blank?
            ary << [:topic, value] # e.g. topic:electron
          else
            ary << [:topic, value, true] # e.g. -topic:electron
          end

        # look for literal strings (inside double quotes)
        elsif scanner.scan(/"/)
          query += scanner[0]
          query += scanner.scan_until(/(^|[^\\])"/).to_s

        # otherwise this (til next whitespace) is part of the query
        else
          text = scanner.scan_until(/\s|$/).to_s
          text = scanner.getch if text.empty? # prevent theoretical infinite loop
          query += text
        end
      end

      ary << query.strip unless query.blank?

      ary
    end

    # Public: Generate a search query String given a parsed query Array.
    #
    # ary - Parsed query Array
    #
    # Examples
    #
    #     stringify(["parser", [:label, "search"], [:author, "TwP"]])
    #     # => "parser label:search author:TwP"
    #
    # Returns a search query String.
    def self.stringify(ary)
      ary.map do |component|
        case component
        when String
          component
        when Array
          key, input_value, negative = component
          output_value = if input_value.is_a?(Array)
            input_value.map { |v| encode_value(v.to_s) }.join(",")
          else
            encode_value(input_value.to_s)
          end
          "#{'-' if negative}#{key}:#{output_value}"
        else
          raise TypeError, "unknown query component: #{component.inspect}"
        end
      end.join(" ")
    end

    # Public: Escape the value part of a query String.
    #
    # value - String value fragment
    #
    # Examples
    #
    #     encode_value(%Q{1.0.0: "The Big One"})
    #     # => "1.0.0: \\\"The Big One\\\""
    #     puts _
    #     # => 1.0.0: \"The Big One\"
    #
    # Returns a search query value String
    def self.encode_value(value)
      if /\s|"/.match?(value)
        safe_value = value.gsub('"', '\"')
        %Q{"#{safe_value}"}
      else
        value
      end
    end

    # Public: Select alls terms matching the block in reverse.
    #
    # Iterates over items in reverse since the right most terms override
    # previous values by convention.
    #
    # ary - Parsed query Array
    #
    # Returns the filtered Array in original order.
    def self.filter_terms(ary, &block)
      ary.reverse.select do |component|
        if component.is_a?(Array)
          key, value, negative = component
          yield key, value, negative
        else
          true
        end
      end.reverse
    end

    def self.asciify_emoji(str)
      str.gsub(GitHub::HTML::EmojiFilter.unicodes_pattern) do |unicode|
        if emoji = Emoji.find_by_unicode(unicode)
          emoji.name
        else
          unicode
        end
      end
    end

    # Returns a new Hash of BoolCollection values that can be used safely as a
    # qualifiers hash.
    def self.qualifiers
      Hash.new { |h, k| h[k] = BoolCollection.new(k) }
    end

    # Private: Apply @me macros to values that allow for replacing the @me with the current viewer's login.
    #          Special note: This method is recursive if the value is an Array but will only traverse for a
    #          maximum of MAX_RECURSION_DEPTH levels.  After MAX_RECURSION_DEPTH levels it will short-circuit
    #          and return the original value(s) lower.  This should provide boundaries and help prevent infinite
    #          recursion / stack level too deep errors.
    def self.apply_me_macro(current_user, field, value, depth = 0)
      # this will ensure our recursion doesn't go too deep and prevent stack level too deep errors
      return value if depth > MAX_RECURSION_DEPTH

      return value unless current_user
      return value.map { |v| apply_me_macro(current_user, field, v, depth + 1) } if value.is_a?(Array)

      if Search::Query::USERNAME_SEARCH_FIELDS.include?(field) && Search::Query::MACRO_ME.casecmp?(value)
        GitHub.dogstats.increment("search.me_macro")
        current_user.display_login
      else
        value
      end
    end

    def self.apply_today_macro(value, current_user, depth = 0)
      return value if depth > MAX_RECURSION_DEPTH
      return value.map { |v| apply_today_macro(v, current_user, depth + 1) } if value.is_a?(Array)

      if value.match /#{Search::Query::MACRO_TODAY}/
        GitHub.dogstats.increment("search.today_macro")
        today = current_user&.time_zone ? Time.now.in_time_zone(current_user.time_zone).to_date : Date.today
        value.gsub("@today", today.strftime("%Y-%m-%d"))
      else
        value
      end
    end

    # The raw search phrase obtained from the user.
    attr_reader :phrase

    # The qualifier terms to parse out of the search phrase.
    attr_reader :terms

    # The query parsed from the search phrase; everything except the qualifier
    # terms.
    attr_reader :query

    # An allow list of terms that an be parsed into "should" query elements
    attr_reader :enumerable_terms

    # The qualifiers parsed the search phrase; this is a Hash of
    # BoolCollection objects keyed by qualifier name.
    attr_reader :qualifiers

    if GitHub.enterprise?
      # the environment is parsed via the search phrase; this is
      # a String either empty or equal to "local" or "github"
      attr_reader :environment
    end

    # Create a new ParsedQuery.
    #
    # phrase - The raw search phrase as a String
    # terms  - An Array of terms to extract from the search phrase
    # current_user - Currently logged in User to use for @me replacement
    # enumerable_terms - An Array of terms that can be parsed as a comma separated list
    def initialize(phrase, terms = [], current_user = nil, enumerable_terms = [])
      @phrase = phrase.to_s
      @terms = terms.flatten.uniq
      @enumerable_terms = enumerable_terms
      @qualifiers = ::Search::ParsedQuery.qualifiers
      @query = parse(current_user)
    end

    # Internal: Parse the query terms and the qualifiers from the raw search
    # phrase. The query terms are used in the query portion of the search, and
    # the qualifiers will be converted into filters.
    #
    # Returns query String from phrase.
    def parse(current_user)
      query = []
      terms = (self.terms + [:repo, :user]).uniq

      self.class.parse(phrase, terms: terms, viewer: current_user, enumerable_terms: enumerable_terms).each do |component|
        case component
        when String
          query << component
        when Array
          key, value, negative = component
          if key == :environment
            @environment = value
          elsif negative
            qualifiers[key].must_not(value)
          else
            if value.is_a?(Array)
              qualifiers[key].and_should(value)
            else
              qualifiers[key].must(value)
            end
          end
        end
      end

      query.join(" ")
    end

    # As we are parsing a query phrase, we want to store the various
    # parts of the query based on their required presence in the search
    # results. This class adopts the ElasticSearch boolean notation of using
    # "must", "must_not", and "should" components for storing this data.
    #
    # Values that have to be present in the search results are stored in the
    # `must` array. Values that cannot be present are stored in the `must_not`
    # array. Optional values are stored in the `should` array.
    #
    # The "and_should" component is meant to collect groups of results. Values
    # in the `and_should` array are themselves arrays, ie `[['a','b'],['c','d']]`.
    # In the query these groups of values are meant to mean "(a or b) and (c or d)".
    # Eventually this collection needs to be transformed into a query or filter.
    class BoolCollection

      # The name of the collection as a Symbol (can be nil).
      attr_reader :name

      # Create a new collection for boolean terms.
      #
      # name - An optional collection name
      def initialize(name = nil)
        @name = name
        clear
      end

      # Clear all the stored components: `must`, `must_not`, `and_should` and `should`.
      #
      # Returns this BoolCollection instance.
      def clear
        @must = nil
        @must_not = nil
        @should = nil
        @and_should = nil
        self
      end

      # Create a copy of this BoolCollection that is independent of this
      # instance. The component Arrays are duplicated
      # so that the new collection can operate on them without affecting this
      # instance.
      #
      # Returns a new BoolCollection instance.
      def dup
        copy = BoolCollection.new @name

        copy.must     = @must.dup     unless @must.nil?
        copy.must_not = @must_not.dup unless @must_not.nil?
        copy.should   = @should.dup   unless @should.nil?
        copy.and_should = @and_should.dup   unless @and_should.nil?

        copy
      end

      # Removes duplicate values from the component arrays.
      #
      # Returns this BoolCollection instance.
      def uniq!
        must.uniq!     if must?
        must_not.uniq! if must_not?
        should.uniq!   if should?
        @and_should = @and_should.map(&:sort).uniq if and_should?

        self
      end

      # Merge the contents of the other BoolCollection into this one. This
      # collection is modified, but the other will remain unchanged.
      #
      # other - The other BoolCollection to merge into this one.
      #
      # Returns this BoolCollection instance.
      # Raises a TypeError if `other` is not a BoolCollection.
      def merge!(other)
        unless other.is_a? BoolCollection
          raise TypeError, "no implicit conversion of #{other.class.name} into #{self.class.name}"
        end

        self.must     = merge_arrays(@must,     other.must)
        self.must_not = merge_arrays(@must_not, other.must_not)
        self.should   = merge_arrays(@should,   other.should)
        self.and_should = merge_arrays(@and_should,   other.and_should)

        self
      end

      # Merge the contents of the other BoolCollection into this one, and
      # return a new collection. Neither collection is modified by this
      # method.
      #
      # other - The other BoolCollection to merge into this one.
      #
      # Returns a new BoolCollection instance.
      # Raises a TypeError if `other` is not a BoolCollection.
      def merge(other)
        unless other.is_a? BoolCollection
          raise TypeError, "no implicit conversion of #{other.class.name} into #{self.class.name}"
        end

        self.dup.merge! other
      end

      # Determine whether the other BoolCollection is equivalent to this one.
      # We require that all the attributes between the two collecitons be the
      # same: `name`, `must` values, `must_not` values, and `should` values.
      #
      # other - The other BoolCollection to test for equality
      #
      # Returns true if the two collections are equal.
      def eql?(other)
        return true if super(other)

        return false unless self.name == other.name
        return false unless self.must == other.must
        return false unless self.must_not == other.must_not
        return false unless self.should == other.should
        return false unless self.and_should == other.and_should

        true
      end
      alias :== :eql?

      # When a `value` is given, it will be added to the Array of `must`
      # components. When nothing is given the current Array of values is
      # returned.
      #
      # value - The value to add to the Array.
      #
      # Returns nil or the Array of values.
      def must(value = nil)
        case value
        when nil
          @must
        when Array
          @must = Array(@must).concat(value)
        else
          @must = Array(@must) << value
        end
      end

      # Returns `true` if there are any `must` components in this boolean
      # collection.
      def must?
        !@must.nil? && !@must.empty?
      end

      # When a `value` is given, it will be added to the Array of `must_not`
      # components. When nothing is given the current Array of values is
      # returned.
      #
      # value - The value to add to the Array.
      #
      # Returns nil or the Array of values.
      def must_not(value = nil)
        case value
        when nil
          @must_not
        when Array
          @must_not = Array(@must_not).concat(value)
        else
          @must_not = Array(@must_not) << value
        end
      end

      # Returns `true` if there are any `must_not` components in this boolean
      # collection.
      def must_not?
        !@must_not.nil? && !@must_not.empty?
      end

      # When a `value` is given, it will be added to the Array of `should`
      # components. When nothing is given the current Array of values is
      # returned.
      #
      # value - The value to add to the Array.
      #
      # Returns nil or the Array of values.
      def should(value = nil)
        case value
        when nil
          @should
        when Array
          @should = Array(@should).concat(value)
        else
          @should = Array(@should) << value
        end
      end

      # Returns `true` if there are any `should` components in this boolean
      # collection.
      def should?
        !@should.nil? && !@should.empty?
      end

      # When a `value` Array is given, it will be pushed onto to the Array of `and_should`
      # components. When nothing is given the current Array of values is
      # returned.
      #
      # value - An Array of values to be added to the current array.
      #
      # Returns nil or the Array of values.
      def and_should(value = nil)
        case value
        when nil
          @and_should
        when Array
          @and_should = Array(@and_should).push(value)
        else
          raise ArgumentError, "and_should only accepts arrays of values"
        end
      end

      # Returns `true` if there are any `and_should` components in this boolean
      # collection.
      def and_should?
        !@and_should.nil? && !@and_should.empty?
      end

      # Returns `true` if all of the components (must, must_not, should) are
      # empty. Returns `false` if any one of the components contains data.
      def blank?
        return false if must? || must_not? || should? || and_should?
        true
      end

      # This fun little method will return the values from _all_ the
      # components. This will be a single Array that might be empty.
      # Duplicates are not removed.
      #
      # Array of all values from the `must`, `must_not`, and `should`
      # components. The `and_should` values are flattened.
      def all
        ary = []
        ary.concat must     if must?
        ary.concat must_not if must_not?
        ary.concat should   if should?
        ary.concat and_should.flatten if and_should?
        ary
      end

      # Mutate all the values stored in the `must`, `must_not`, and `should`
      # component arrays. The inner values of the `and_should` array will also
      # be mutated. The _block_ will be used to change values via the
      # the `Array#map!` method.
      #
      # Returns this BoolCollection.
      def map_all!(&block)
        must.map!(&block).compact!     if must?
        must_not.map!(&block).compact! if must_not?
        should.map!(&block).compact!   if should?
        and_should.map! { |inner| inner.map(&block).compact } if and_should?
        self
      end

      # Mutate all the values stored in the `must`, `must_not`, and `should`
      # component arrays. The _block_ will be used to change values in-place
      # in a manner consistent with the `Array#flat_map` method: the _block_
      # may return an Array containing zero, one, or many replacement values
      # for each yielded value.
      #
      # Returns this BoolCollection.
      def flatmap_all!(&block)
        must.map!(&block).flatten!.compact! if must?
        must_not.map!(&block).flatten!.compact! if must_not?
        should.map!(&block).flatten!.compact! if should?
        and_should.map! { |inner| inner.map(&block).flatten.compact } if and_should?
        self
      end

      # Remove the `must_not` values from the `must` and `should`, and `and_should` componenets.
      #
      # Returns this BoolCollection.
      def intersect!
        return self unless must_not?
        @must   -= must_not if must?
        @should -= must_not if should?
        @and_should = @and_should.map { |inner| inner - must_not } if and_should?
        self
      end

      # Internal setter for the `must` attribute.
      attr_writer :must

      # Internal setting for the `must_not` attribute.
      attr_writer :must_not

      # Internal setting for the `should` attribute.
      attr_writer :should

      # Internal setting for the `and_should` attribute.
      attr_writer :and_should

      protected

      # Internal: Helper method that will merge two Arrays and return the
      # result. The second Array will be merged into the first and the first
      # will be returned. If the first Array is nil then the second Array is
      # duplicated.
      #
      # ary1 - The first Array (or nil)
      # ary2 - The second Array (or nil)
      #
      # Returns nil, the first Array, or a duplicate of the second Array.
      def merge_arrays(ary1, ary2)
        return if ary1.nil? && ary2.nil?
        return ary2.dup if ary1.nil?
        return ary1     if ary2.nil?

        ary1.concat ary2
      end
    end

  end
end
