# typed: true
# frozen_string_literal: true

# Public: A convenient way to generate fully-qualified Google Analytics URLs
# for use in things like email messages where tracking can't be done with
# session or flash storage + JS.
#
# Validates that all required GA parameters are present, mutating them into the
# `utm_` format.
#
# See Also: UrlHelper#ga_campaign_url
#
# Examples
#
#   # Correctly specifying the required Google Analytics parameters:
#   GitHub::GACampaignURL.new("/path/to/things", :source   => "verification-email",
#                                                :medium   => "email",
#                                                :campaign => "github-email-verification")
#   # => #<GitHub::GACampaignURL:0x007fdf2adb2340 @path="/path/to/things", @query_params={:source=>"verification-email", :medium=>"email", :campaign=>"github-email-verification"}>
#   _.to_s
#   # => "https://github.com/path/to/things?utm_campaign=github-email-verification&utm_medium=email&utm_source=verification-email"
#
#   # Incorrectly leaving off the required parameters:
#   GitHub::GACampaignURL.new("/")
#   # => ArgumentError: Missing required params: source, medium, campaign
module GitHub
  class GACampaignURL
    REQUIRED_PARAMS = %w[source medium campaign].freeze
    OPTIONAL_PARAMS = %w[term content].freeze
    CAMPAIGN_PARAMS = (REQUIRED_PARAMS + OPTIONAL_PARAMS).freeze

    attr_reader :destination_uri, :query_params

    def initialize(destination, query_params = {})
      @destination_uri = URI.parse(destination)
      @query_params = query_params

      validate_query_params
    end

    # Public: Get the URI for this GACampaignURL
    #
    # Returns a URI::HTTPS or URI::HTTP object representing the destination URI
    # with properly formatted Google Analytics campaign parameters
    def uri
      URI.parse(host_with_scheme).tap do |uri|
        uri.path = destination_uri.path
        uri.query = query_string
      end
    end

    # Public: The full, raw URI string for this GACampaignURL
    def to_s
      uri.to_s
    end

    # Public: All of the Google Analytics campaign params, remapped into their
    # UTM form
    #
    # Returns a hash of query keys and their values
    def utm_query_params
      remapped = filtered_query_params.map { |key, value| ["utm_#{key}", value] }
      Hash[remapped]
    end

    # Public: All non-Google Analytics query parameters, which can come from
    # the path and/or the parameter hash
    #
    # Returns a hash of query keys and their values
    def extra_query_params
      destination_query_hash = Rack::Utils.parse_nested_query(destination_uri.query)
      query_hash = query_params.select do |key, _|
        !CAMPAIGN_PARAMS.include?(key.to_s)
      end

      destination_query_hash.merge(query_hash)
    end

    # Public: All query params (campaign and non-campaign) as a query string
    #
    # Examples
    #
    #   ga_campaign_url.query_string
    #   # => "any_query_param=goes_here&utm_campaign=A&utm_medium=B&utm_source=C"
    #
    # Returns the query portion of the URL
    def query_string
      extra_query_params.merge(utm_query_params).to_query
    end

    private

    def destination_uri_absolute?
      !!destination_uri.host
    end

    def host_with_scheme
      if destination_uri_absolute?
        URI::Generic.build(scheme: destination_uri.scheme, host: destination_uri.host).to_s
      else
        GitHub.url
      end
    end

    # Private: Filter down to just the Google Analytics query params
    def filtered_query_params
      query_params.select do |key, _|
        CAMPAIGN_PARAMS.include?(key.to_s)
      end
    end

    def required_params_missing
      REQUIRED_PARAMS - query_params.keys.collect(&:to_s)
    end

    def required_params_blank
      query_params.select do |key, value|
        REQUIRED_PARAMS.include?(key.to_s) && value.blank?
      end.keys
    end

    def invalid_params
      required_params_missing + required_params_blank
    end

    def valid?
      invalid_params.none?
    end

    def validate_query_params
      unless valid?
        list = invalid_params.uniq.join(", ")
        raise ArgumentError.new("Missing required params: #{list}")
      end
    end
  end
end
