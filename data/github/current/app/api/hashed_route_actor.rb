# typed: true
# frozen_string_literal: true

module Api
  class HashedRouteActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    attr_reader :flipper_id
    attr_reader :route_pattern

    # Known identifier components
    COMPONENT_ROUTE = :route
    COMPONENT_ASN = :asn
    COMPONENT_JA3 = :ja3

    # Mapping of component prefixes in the ID string
    COMPONENT_PREFIXES = {
      COMPONENT_ROUTE => "/",
      COMPONENT_ASN => "asn",
      COMPONENT_JA3 => "ja3"
    }.freeze

    # Mapping of environment keys to component types
    ENV_HEADER_MAPPING = {
      "github.api.route" => COMPONENT_ROUTE,
      "HTTP_X_AS" => COMPONENT_ASN,
      "HTTP_X_SSL_JA3_HASH" => COMPONENT_JA3
    }.freeze

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def self.from_env(env)
      components, original_route_pattern = extract_components_from_env(env)
      new_from_components(components, original_route_pattern: original_route_pattern)
    end

    def self.extract_components_from_env(env)
      components = {}
      original_route_pattern = nil

      # Extract route pattern and hash it
      route_pattern_env_key = ENV_HEADER_MAPPING.key(COMPONENT_ROUTE)
      pattern = env[route_pattern_env_key]
      if pattern.present?
        original_route_pattern = pattern
        # hash of the route pattern as dev portal doesn't allow most symbols for feature flagging
        components[COMPONENT_ROUTE] = Digest::SHA1.hexdigest(pattern) # rubocop:disable GitHub/InsecureHashAlgorithm
      else
        GitHub.logger.warn("No route_pattern found for RouteActor")
      end

      # Extract other headers
      ENV_HEADER_MAPPING.each do |env_key, component_key|
        next if component_key == COMPONENT_ROUTE
        if value = env[env_key]
          components[component_key] = value if value.present?
        end
      end

      [components, original_route_pattern]
    end

    def self.new_from_components(components, original_route_pattern: nil)
      id_parts = []

      if route_hash_val = components[COMPONENT_ROUTE]
        id_parts << "#{COMPONENT_PREFIXES[COMPONENT_ROUTE]}#{route_hash_val}"
      end

      if asn = components[COMPONENT_ASN]
        id_parts << "#{COMPONENT_PREFIXES[COMPONENT_ASN]}#{asn}"
      end

      if ja3 = components[COMPONENT_JA3]
        id_parts << "#{COMPONENT_PREFIXES[COMPONENT_JA3]}#{ja3}"
      end

      new(id_parts.join("-"), original_route_pattern: original_route_pattern)
    end

    # id format: "/routehash-asnASN-ja3JA3"
    # e.g "/asd88776asdlkjas9-asnA11876-ja312jk3k123j123"
    def initialize(id, original_route_pattern: nil)
      return if id.nil?

      @components = {}

      id.split("-").each do |part|
        COMPONENT_PREFIXES.each do |component, prefix|
          if part.start_with?(prefix)
            value = part.delete_prefix(prefix)
            @components[component] = value
            break
          end
        end
      end

      return if @components[COMPONENT_ROUTE].nil?

      # Prepend with the class name for feature flagging
      @flipper_id = "#{self.class.name}:#{id}"
      @vexi_id = @flipper_id
      @route_pattern = original_route_pattern
    end

    def is_valid?
      return false if @components.nil?
      return false if @components[COMPONENT_ROUTE].nil? # This checks for the hash
      true
    end

    def route_hash # Renamed from 'route'
      @components[COMPONENT_ROUTE]
    end

    def asn
      @components[COMPONENT_ASN]
    end

    def ja3
      @components[COMPONENT_JA3]
    end

    # return the specific combination of attributes that match the configured actor in the FF
    def blocked_actor(feature_flag_name = :api_block_anonymous_by_hashed_route)
      # full match on route/asn/ja3
      return self if FeatureFlag.vexi.enabled?(feature_flag_name, self, default: false)

      # match on route/asn
      local_route_asn_actor = route_asn_actor
      return local_route_asn_actor if FeatureFlag.vexi.enabled?(feature_flag_name, local_route_asn_actor, default: false)

      # match on route/ja3
      local_route_ja3_actor = route_ja3_actor
      return local_route_ja3_actor if FeatureFlag.vexi.enabled?(feature_flag_name, local_route_ja3_actor, default: false)

      # match on route only
      local_route_actor = route_actor
      return local_route_actor if FeatureFlag.vexi.enabled?(feature_flag_name, local_route_actor, default: false)

      nil
    end

    def route_asn_ja3_id
      to_s
    end

    def route_asn_id
      build_partial_id([COMPONENT_ROUTE, COMPONENT_ASN])
    end

    def route_ja3_id
      build_partial_id([COMPONENT_ROUTE, COMPONENT_JA3])
    end

    def route_id
      build_partial_id([COMPONENT_ROUTE])
    end

    def route_asn_actor
      self.class.new(route_asn_id)
    end

    def route_ja3_actor
      self.class.new(route_ja3_id)
    end

    def route_actor
      self.class.new(route_id)
    end

    def to_s
      @flipper_id
    end

    def vexi_id
      @vexi_id
    end

    private

    # Helper method to build partial IDs with specific components
    def build_partial_id(component_keys)
      parts = component_keys.map do |key|
        if value = @components[key]
          "#{COMPONENT_PREFIXES[key]}#{value}"
        end
      end.compact

      parts.join("-")
    end
  end
end
