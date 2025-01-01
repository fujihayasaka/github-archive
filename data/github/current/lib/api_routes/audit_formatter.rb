# typed: true
# frozen_string_literal: true
module ApiRoutes
  class AuditFormatter
    attr_reader :collection
    def initialize(collection)
      @collection = collection
    end

    def print
      rows = collection.endpoints.map do |endpoint|
        Row.new(endpoint)
      end

      authz_width = ([10] + collection.endpoints.map { |v| v.control_access_calls.map(&:verb).join(", ").length }).max
      endpoint_width = ([10] + collection.endpoints.map { |v| v.to_s.length + 6 }).max # +6 accounts for the markdown link

      header = [
        "Server-Server".center(18),
        "User-Server".center(18),
        "AuthZ".center(authz_width),
        "Endpoint".ljust(endpoint_width),
      ].join(" | ")
      hr = "| %s |" % ("-" * header.length)

      puts "## [%s](%s)\n\n" % [collection.namespace, "##{collection.namespace.underscore.parameterize.dasherize}"]
      puts "| %s |" % header
      puts "| %s | %s | %s | %s |" % ["-" * 18, "-" * 18, "-" * authz_width, "-" * endpoint_width]
      rows.each do |row|
        puts "| %s |" % [row.s2s.center(18), row.u2s.center(18), row.authz.ljust(authz_width), ("[%s][]" % row.endpoint).ljust(endpoint_width)].join(" | ")
      end
      puts
      collection.endpoints.each do |endpoint|
        puts "[%s]: %s" % [endpoint.to_s, endpoint.source_url]
      end

      puts
    end

    class Row
      attr_reader :endpoint, :authz, :s2s, :u2s
      def initialize(endpoint)
        @endpoint = endpoint.to_s
        @authz = endpoint.control_access_calls.map(&:verb).join(", ")
        if endpoint.audited?
          @s2s = endpoint.enabled_for_integrations? ? yepp : nope
          @u2s = endpoint.enabled_for_user_via_integrations? ? yepp : nope
        else
          if endpoint.enabled_for_integrations?
            @s2s = maybe
          elsif endpoint.control_access_calls.empty?
            @s2s = probably_not
          else
            @s2s = endpoint.control_access_calls.all?(&:enabled?) ? low_hanging_fruit : probably_not
          end
          @u2s = endpoint.enabled_for_user_via_integrations? ? maybe : probably_not
        end
      end

      private

      def maybe
        ":heavy_check_mark:"
      end

      def probably_not
        ":x:"
      end

      def yepp
        ":white_check_mark:"
      end

      def nope
        ":no_entry:"
      end

      def low_hanging_fruit
        ":cherries:"
      end
    end
  end
end
