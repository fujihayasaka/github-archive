# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Emulates some of Nokogiri/libxml2's behavior to make it easier to compare
  # HTML::Pipeline and Goomba output (e.g., in a Scientist experiment).
  class NokogiriCompatibilityFilter < NodeFilter
    SELECTOR = ::Goomba::Selector.new("[href], [action], [src], a[name], [checked], [disabled]")

    def selector
      SELECTOR
    end

    def call(element)
      escape_url_attributes(element)
      expand_boolean_attributes(element)
      element
    end

    private

    ALLOWED_URL_CHARACTERS = Set.new([
      # IS_UNRESERVED(x)
      # From https://github.com/ConradIrwin/libxml2/blob/b368604d9ba04fec68dbc93733e1c2737766747e/uri.c#L87-L91
      "a".."z",
      "A".."Z",
      "0".."9",
      "-_.!~*'()".chars,

      # https://github.com/ConradIrwin/libxml2/blob/b368604d9ba04fec68dbc93733e1c2737766747e/HTMLtree.c#L710
      "@/:=?;#%&,+".chars,
    ].flat_map { |range| range.map(&:ord) })

    # libxml2 encodes href, action, src, and <a name> attributes. Do the same
    # here to match. See https://github.com/ConradIrwin/libxml2/blob/b368604d9ba04fec68dbc93733e1c2737766747e/HTMLtree.c#L700-L710
    def escape_url_attributes(element)
      attributes = %w(href action src)
      if element.tag == :a
        attributes << "name"
      end

      attributes.each do |attr|
        value = element[attr]
        next unless value
        element[attr] = value.each_byte.map { |b| ALLOWED_URL_CHARACTERS.include?(b) ? b.chr : sprintf("%%%02X", b) }.join("")
      end
    end

    def expand_boolean_attributes(element)
      %w[checked disabled].each do |attr|
        element[attr] = attr if element[attr]
      end
    end
  end
end
