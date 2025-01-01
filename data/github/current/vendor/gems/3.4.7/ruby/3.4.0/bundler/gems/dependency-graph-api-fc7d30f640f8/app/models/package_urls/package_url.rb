require "uri"

class MalformedPackageUrlError < StandardError; end

module PackageUrls
  class PackageUrl
    attr_reader :type, :namespace, :name, :version, :qualifiers, :sub_path

    PURL_SCHEME = "pkg".freeze

    class << self
      def from_purl(purl:)
        result = valid_purl(purl: purl)
        raise MalformedPackageUrlError, result[:errors] unless result[:is_valid]
        result[:purl]
      end

      def from_package_release(package_manager:, name:, version:)
        raise ArgumentError if name.blank? || version.blank? || package_manager.blank?
        purl_type = Types::PackageManager.coerce(package_manager).purl_type
        namespace, package_name = parse_package_name(purl_type, name)

        PackageUrl.new(
          type: purl_type,
          namespace: namespace,
          name: package_name,
          version: version,
        )
      end

      def parse_package_name(purl_type, package_name)
        namespace = nil
        package_name = package_name

        # ecosystems with namespaces
        case purl_type
        when "maven"
          parsed_name = package_name.split(":")
          namespace, package_name = parsed_name if parsed_name.size == 2
        when "npm", "composer", "golang", "githubactions"
          parsed_name = package_name.split("/")
          package_name = parsed_name.last
          # depending on the ecosystem, this could be a 1...n length array.
          # Assumption: We don't need to be too concerned about ecosystem specific validation (e.g. support one '/', or more?)
          # Assumption: All ecosystems keep the name in the last segment after splitting on "/"
          namespace_parts = parsed_name[0...-1]
          # namespace parts need to be escaped to be valid PURL -- PURL bans "/" from showing up in this escaped output, our split
          # above provides us some protection (we're still not validating that someone didn't manually embed an escaped "/" though )
          namespace_parts = namespace_parts.map { |np| CGI.unescape(np) }
          namespace = namespace_parts.join("/")
          package_name = parsed_name.last
        end

        return namespace, normalize_name(purl_type, package_name)
      end

      def ensure_valid_type(type)
        result = valid_type(type)
        raise ArgumentError, result[:errors] unless result[:is_valid]
        normalize_type(type)
      end

      def ensure_valid_name(type, name)
        result = valid_name(name)
        raise ArgumentError, result[:errors] unless result[:is_valid]
        normalize_name(type, name)
      end

      def valid_purl(purl:)
        response = {
          is_valid: false
        }

        if purl.blank?
          response[:errors] = ["Invalid PackageURL provided"]
          return response
        end

        begin
          uri = URI(purl)
        rescue URI::Error => exception
          response[:errors] = "PackageURL could not be parsed: #{exception.message}"
          return response
        end

        if uri.scheme != PURL_SCHEME
          response[:errors] = ["Invalid PackageURL scheme provided"]
          return response
        end

        # remainder of PURL as component parsing is done
        # remove "pkg:"
        remainder = purl.slice(PURL_SCHEME.length+1..-1)

        # Optional Subpath
        if remainder.include? "#"
          index = remainder.rindex("#")
          sub_path = trim(remainder[index+1..-1], "/")
          sub_path = unescape_segments(sub_path) if sub_path.present?
          remainder = remainder[0..index-1]
        end

        # Optional Qualifiers
        if remainder.include? "?"
          index = remainder.rindex("?")
          qualifiers = parse_qualifiers(remainder[index+1..-1])
          remainder = remainder[0..index-1]
        end

        # Optional Version
        if remainder.include? "@"
          index = remainder.rindex("@")
          version = remainder[index+1..-1]
          remainder = remainder[0..index-1]
        end

        version = normalize_version(version) if version.present?

        # pieces left consist of type, optional namespace and name
        remainder = trim(remainder, "/")
        required_parts = remainder.split("/").reject(&:empty?)

        if required_parts.length < 2
          response[:errors] = ["Invalid PackageURL, it requires type and name"]
          return response
        end

        errors = []
        result = valid_type(required_parts[0])
        if result[:is_valid]
          type = normalize_type(required_parts[0])
        else
          errors.concat(result[:errors])
        end

        result = valid_name(required_parts[required_parts.length - 1])
        if result[:is_valid]
          name = normalize_name(type, required_parts[required_parts.length - 1])
        else
          errors.concat(result[:errors])
        end

        if required_parts.length > 2
          # remove type and name from array
          sub_parts = required_parts[1..required_parts.length-2]
          namespace = sub_parts.reject(&:blank?).join("/")
          namespace = CGI.unescape(namespace) if namespace.present?
        end

        is_valid = errors.empty?
        purl = is_valid ? PackageUrl.new(type: type, namespace: namespace, name: name, version: version, qualifiers: qualifiers, sub_path: sub_path) : nil

        {
          is_valid: is_valid,
          errors: errors,
          purl: purl
        }
      end

      TYPE_REGEX = /^[a-zA-Z][a-zA-Z0-9.+-]+$/.freeze

      def valid_type(type)
        errors = []
        errors.push("PackageURL Type cannot be nil or empty") if type.blank?

        errors.push("PackageURL Type is invalid") if TYPE_REGEX.match(type).blank?

        {
          is_valid: errors.empty?,
          errors: errors
        }
      end

      def valid_name(name)
        errors = []
        errors.push("PackageURL Name cannot be nil or empty") if name.blank?

        {
          is_valid: errors.empty?,
          errors: errors
        }
      end

      def normalize_type(type)
        type.downcase
      end

      def normalize_name(type, name)
        name = name.gsub("_", "-") if type == "pypi"
        name = name.downcase unless type == "nuget"
        CGI.unescape(name)
      end

      def normalize_version(version)
        CGI.unescape(version) if version.present?
      end

      def parse_qualifiers(qualifiers)
        return qualifiers if qualifiers.is_a?(Hash)

        qualifiers_array = qualifiers&.split("&") || []

        hash = {}
        qualifiers_array.each do |qualifier|
          next unless qualifier.include? "="
          pair = qualifier.split("=")
          hash[pair[0]] = CGI.unescape(pair[1])
        end

        hash.sort.to_h
      end

      def trim(value, string)
        value&.delete_prefix(string)&.delete_suffix(string)
      end

      def unescape_segments(s)
        segments = s.split("/")
        segments.map { |segment| CGI.unescape(segment) }.join("/")
      end
    end

    def initialize(type:, namespace: nil, name:, version: nil, qualifiers: nil, sub_path: nil)
      @type = self.class.ensure_valid_type(type)
      @namespace = namespace
      @name = self.class.ensure_valid_name(type, name)
      @version = version
      @qualifiers = self.class.parse_qualifiers(qualifiers)
      @sub_path = self.class.trim(sub_path, "/")
    end

    def to_purl
      purl_array = []
      purl_array.push("#{PURL_SCHEME}:")
      purl_array.push(type) if type.present?
      purl_array.push("/")
      purl_array.push(escape_segments(namespace) + "/") if namespace.present?
      purl_array.push(CGI.escape(name)) if name.present?
      purl_array.push("@" << CGI.escape(version)) if version.present?

      if qualifiers.present?
        purl_array.push("?")
        qualifiers.each do |k, v|
          next if v.blank?
          # key must not be percent encoded
          purl_array.push(k.to_s.downcase << "=" << CGI.escape(v))
          purl_array.push("&")
        end

        purl_array.pop
      end

      purl_array.push("#" << escape_segments(sub_path)) if sub_path.present?
      # convert to string
      purl_array.join
    end

    def escape_segments(s)
      segments = s.split("/")
      segments.map { |segment| CGI.escape(segment) }.join("/")
    end

    # Returns the type translated to our dg-api PackageManager types
    def type_dg_api
      return Types::PackageManager[:unknown] unless type.present?

      Types::PackageManager.by(:purl_type, type.downcase)
    rescue ArgumentError
      Types::PackageManager[:unknown]
    end

    # We need to know how to construct what other parts of github consider a package's "name",
    # this is often some combination of namespace and name with a separator.
    # E.g. for a purl for NPM, it might look like pkg:/npm/%40action/http-client@1.0.0
    #  The namespace is "@action" which needs to be combined with name to produce a full_package_name of @action/http-client.
    # The separator or format varies from ecosystem to ecosystem, for example maven is <namespace>:<packageName>
    def full_package_name
      # See https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst
      # This is implicitly coupled to how a package would compute "full package name" from PURL's namespace and name.
      case type.downcase
      when "maven"
        namespace_with_name(":")
      when "npm", "composer", "golang", "githubactions"
        namespace_with_name("/")
      when "nuget", "pypi", "gem", "cargo", "pub"
        # intentionally no namespace delimiter, as the purl type def doesn't include one.
        name
      else
        # unclassified -- we choose to intentionally return the forward slash delimiter because it's our best guess.
        namespace_with_name("/")
      end
    end

    def ==(other)
      @type == other.type \
      && @namespace == other.namespace \
      && @name == other.name \
      && @version == other.version \
      && @qualifiers == other.qualifiers \
      && @sub_path == other.sub_path
    end

    def <=>(other)
      key.<=>(other.key)
    end

    def eql?(other)
      self.==(other)
    end

    def key
      to_purl
    end

    def hash
      key.hash
    end

    # private
    def namespace_with_name(delimiter)
      # namespace in PURL can be multiple segments, '/' delimited. Each segment will be escaped, so in order
      # to get back to namespace_with_name (this is specifically not the PURL concept but the logical namespace + name)
      # we need to unescape all segments before concatenating.
      # Purl syntax would be: pkg:npm/%40angular/animation@12.3.1
      # namespace_with_name would return: @angular/animation
      if namespace.present?
        namespace_segments = namespace.split("/")
        unescaped_namespace = namespace_segments.map { |ns| CGI.unescape(ns) }.join("/")
        return "#{unescaped_namespace}#{delimiter}#{name}"
      end

      return name
    end
  end
end
