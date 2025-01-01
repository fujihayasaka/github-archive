# typed: true
# frozen_string_literal: true

require "github/sms/error"

module GitHub
  module SMS
    autoload :Local, "github/sms/local"
    autoload :Nexmo, "github/sms/nexmo"
    autoload :Provider, "github/sms/provider"
    autoload :Receipt, "github/sms/receipt"
    autoload :Test, "github/sms/test"
    autoload :TestTwo, "github/sms/test_two"
    autoload :Twilio, "github/sms/twilio"

    include GitHub::RateLimitable
    PROVIDERS = {
      production: {
        "91": [Nexmo], # India
        "971": [Nexmo], # UAE
        "62": [Nexmo], # Indonesia
        "30": [Nexmo], # Greece
        "7": [Nexmo], # Russia
        "90": [Twilio], # Türkiye
        "86": [Twilio], # China
        "244": [Twilio], # Angola
        "default": [Nexmo, Twilio],
      },
      development:  {
        "default": [Local, Local]
      },
      test: {
        "91": [Test],
        "971": [TestTwo],
        "default": [Test, TestTwo]
      }
    }.with_indifferent_access

    # This is a mapping of country code to optimal provider. Mainly for cost optimization.
    #
    # To update this mapping, clone the `github/authentication` repo and run the following command:
    # ```
    # cd tools/sms_provider_cost_analyzer; npm i; npm start
    # ````
    # this will generate a report with costs per provider and country code
    # and will output the cheaper country codes for each provider based on pricing data for each provider and a threshold
    OPTIMIZED_PROVIDER_MAPPING = {
      production: {
        # Nexmo
        "7": Nexmo, # Russia & Kazakhstan
        "62": Nexmo, # Indonesia
        "34": Nexmo, # Spain
        # Twilio
        "593": Twilio, # Ecuador
        "218": Twilio, # Libya
        "261": Twilio, # Madagascar
      },
      development: {},
      test: {
        "7": Test,
        "593": TestTwo,
        "91": TestTwo,
      }
    }.with_indifferent_access

    # Number of times to attempt SMS delivery.
    DELIVERY_ATTEMPTS = 2

    # Regexp for splitting out the country code from a phone number.
    PHONE_NUMBER_PARTS_REGEX = /\A\+(\d+) (.+)\z/

    # Rate limit constants used to configure a rate limiter to prevent unbounded
    # SMS messages sent to a given number.
    SMS_RATE_LIMIT_MAX_TRIES = 10
    SMS_RATE_LIMIT_TTL = 10.minutes

    # Public: Try delivering an SMS using a random ordering of available SMS
    # providers. Only try DELIVERY_ATTEMPTS times.
    #
    # to       - The number to send the message to.
    # message  - The message to send.
    # options  - A Hash of optional settings.
    #            :attempts - The number of attempts to make.
    #            :provider - The provider to send the message with or the name
    #                        of the provider.
    #            :reason - A reason (symbol) for sending the message.
    #                      Defaults to :unknown. Used for stats.
    #            :completed_captcha - (Boolean) User was shown and completed a CAPTCHA before SMS was sent.
    #
    # Returns a GitHub::SMS::Receipt. Raises GitHub::SMS::Error.
    def send_message(to, message, user, options = {})
      to = normalize_for_provider(to)
      raise RateLimitError if rate_limited?(to)

      attempts = options.fetch(:attempts, DELIVERY_ATTEMPTS)
      reason = options.fetch(:reason, :unknown)
      completed_captcha = options.fetch(:completed_captcha, false)
      provider = get_provider(options[:provider])

      provider.send_message(to, message, user, reason, completed_captcha)
    rescue ServerError, NumberNotMobileError, BillingError, RegionNotGeoPermissionedError => e
      if attempts > 1
        send_message(to, message, user,
          attempts: (attempts - 1),
          provider: get_alternate_provider(to, provider),
          reason: reason,
          completed_captcha: completed_captcha
        )
        GitHub.dogstats.increment("sms.rescue_retry", tags: ["provider:#{provider.provider_name}", "reason:#{reason}", "completed_captcha:#{completed_captcha}", "attempts:#{attempts}", "error:#{e.class.name}"])
      else
        raise
      end
    end

    # Parses a phone number string into e164 format:
    # https://en.wikipedia.org/wiki/E.164
    #
    # Used at "send time" to prepare the number for the provider
    #
    # Returns an e164 formatted String
    def normalize_for_provider(number)
      parsed = Phonelib.parse(number)
      raise NumberNotValidError unless parsed.valid?
      parsed.e164
    end

    # Public: Gets the provider for a given number.
    #
    # Supports attempting to use an optimized provider for the given number if a known provider is not provided and the number is not special cased
    # Supports attempting to use an alternate provider for the given number with a last used provider
    def provider_for(number, known_provider:, last_used_provider:, attempt_alternate:)
      country_code = Phonelib.parse(number)&.country_code

      # Certain countries have special case providers where we only ever use the one provider.
      if country_has_special_case_provider?(country_code)
        return first_provider_for_country_code(country_code)
      end

      if attempt_alternate
        return get_alternate_provider(number, last_used_provider)
      end

      if known_provider
        return get_provider(known_provider)
      end

      # Only attempt to use the optimized provider if we don't have a known provider
      # Fallback to the default provider if we don't have an optimized provider
      optimized_provider_for_country_code(country_code) || get_provider
    end

    private def optimized_provider_for_country_code(country_code)
      @optimized_provider_for_country_code ||= Hash.new do |h, key|
        h[key] = OPTIMIZED_PROVIDER_MAPPING[Rails.env][key]&.send(:new)
      end

      @optimized_provider_for_country_code[country_code]
    end

    # Get the primary provider to use given an optionally configured provider.
    #
    # provider - A String/Symbol provider name or Provider subclass instance.
    #
    # Returns a Provider instance subclass.
    def get_provider(provider = nil)
      case provider
      when String, Symbol
        find_provider_by_name(provider)
      when Provider
        provider
      when nil
        providers_for_env.first
      end
    end

    # Get the alternate provider to use given an optionally configured primary
    # provider.
    #
    # number - The destination phone number to get the alternate provider for. Used for special cases, i.e. India and UAE.
    # provider - The Provider or provider name that shouldn't be returned.
    #
    # Return a Provider instance.
    private def get_alternate_provider(number, provider)
      country_code = Phonelib.parse(number)&.country_code unless number.nil?

      # always use the special case provider if it's defined
      if country_has_special_case_provider?(country_code)
        first_provider_for_country_code(country_code)
      else
        # Resolve String, Symbol, nil providers.
        provider = get_provider(provider) unless provider.is_a?(Provider)

        if providers_for_env.first == provider
          providers_for_env.last
        else
          providers_for_env.first
        end
      end
    end

    # Get a Provider instance by name.
    #
    # name - The Symbol or String name of the provider.
    #
    # Returns a Provider instance.
    def find_provider_by_name(name)
      name = name.to_sym
      providers_for_env.find do |provider|
        provider.provider_name == name
      end
    end

    # Public: Memoized random ordering of providers for this environment.
    #
    # Returns an Array of instances of subclasses of SMS::Provider.
    def providers_for_env
      @providers_for_env ||= PROVIDERS[Rails.env]["default"].map(&:new)
    end

    def country_has_special_case_provider?(country_code)
      @country_has_special_case_provider ||= Hash.new do |h, key|
        h[key] = PROVIDERS[Rails.env][key].present?
      end

      @country_has_special_case_provider[country_code]
    end

    def first_provider_for_country_code(country_code)
      @first_provider_for_country_code ||= Hash.new do |h, key|
        h[key] = PROVIDERS[Rails.env][key]&.first&.send(:new)
      end

      @first_provider_for_country_code[country_code]
    end

    # Public: Normalize a phone number.
    # A normalized phone number should start with `+`, followed by the country
    # code, then a space, then the body of the number. Eg. `+1 7736829478`
    #
    # Used to provide a consistent phone format in our database.
    #
    # number - A phone number String.
    #
    # Returns a normalized phone number String.
    def normalize_number(number)
      # Make sure we don't have a weird type from params.
      number = number.to_s

      # Split out country code.
      match = number.match(PHONE_NUMBER_PARTS_REGEX)
      raise NumberNotValidError unless match
      country, number = match[1..2]

      # Remove any non-numeric characters from number.
      number.gsub!(/\D/, "")

      # Strip any leading zeros.
      # This allows the user to enter leading numbers in the UI, but keeps our DB consistent by stripping them off before they are saved
      # Do NOT strip off the zeros if the number is detected as an Ivory Coast number
      number.sub!(/\A0+/, "") unless from_ivorycoast?(country)

      # Check that the number isn't empty now that we stripped non-numeric chars
      raise NumberNotValidError if number.empty?

      # Sweet reunion
      "+#{country} #{number}"
    end

    # Check if the country code belongs to Ivory Coast
    # Used to allow leading zeros
    # As of January 31, 2021, Ivory Coast changed their national number format
    # from an 8-digit format (after the international dialing code) to a 10-digit format that includes a leading zero.
    def from_ivorycoast?(country_code)
      # 225 is the country code for Ivory Coast
      country_code == "225"
    end

    # Public: Checks if a phone number is correctly formatted.
    #
    # number - A phone number String.
    # use_phonelib - A boolean indicating whether to use Phonelib for additional validation of the number. Defaults to false.
    #
    # Returns boolean.
    def valid_number?(number, use_phonelib: false)
      match = number.match(PHONE_NUMBER_PARTS_REGEX)
      return false if !match
      country = match[1]

      valid_format = true
      if from_ivorycoast?(country)
        # Valid phone number Regexp - allowing leading 0 (Eg. "+225 0101286981")
        valid_format = !!(/\A\+\d+ \d+\z/ =~ number)
      else
        # By default, we do not allow leading 0s
        # This logic was intentionally added in 2015 to improve consistency of our calls to Nexmo:
        # https://github.com/github/github/pull/38884
        # Valid phone number Regexp - does not allow leading 0 (Eg. "+1 7736829478")
        valid_format = !!(/\A\+\d+ [1-9]\d*\z/ =~ number)
      end
      return valid_format if !valid_format || !use_phonelib
      !!Phonelib.parse(number)&.valid?
    end

    # Public: Checks if a phone number uses a country code that is supported
    #
    # number - A phone number String.
    #
    # Returns boolean.
    def valid_country?(number)
      country_code = normalize_number(number).split(" ").first

      valid_country_code?(country_code)
    end

    # Public: Checks if a given country code is supported
    #
    # country_code - A country code String, may or may not include a leading `+`
    #
    # Returns boolean.
    def valid_country_code?(country_code)
      SUPPORTED_COUNTRIES.map(&:first).include?(country_code) ||
        SUPPORTED_COUNTRIES.map(&:first).include?("+" + country_code)
    end

    # Public: Checks if we should stop sending SMS messages to a given number.
    #
    # number - A phone number String.
    #
    # Returns boolean.
    def rate_limited?(number)
      return false unless number.present?

      options = {
        max_tries: SMS_RATE_LIMIT_MAX_TRIES,
        ttl: SMS_RATE_LIMIT_TTL,
      }

      at_limit = rate_limit_increment("sms-rate-limit:#{number}", options).at_limit?

      if at_limit
        GitHub.dogstats.increment("sms.rate_limited")
      end
      at_limit
    end

    # Some countries share a country code so we keep this in a nested array
    COUNTRY_CODES = [
      ["+93",   "Afghanistan"],
      ["+358",  "Aland Islands"],
      ["+355",  "Albania"],
      ["+213",  "Algeria"],
      ["+1684", "American Samoa"],
      ["+376",  "Andorra"],
      ["+244",  "Angola"],
      ["+1264", "Anguilla"],
      ["+1268", "Antigua and Barbuda"],
      ["+54",   "Argentina"],
      ["+374",  "Armenia"],
      ["+297",  "Aruba"],
      ["+247",  "Ascension"],
      ["+61",   "Australia"],
      ["+43",   "Austria"],
      ["+994",  "Azerbaijan"],
      ["+1",    "Bahamas"],
      ["+973",  "Bahrain"],
      ["+880",  "Bangladesh"],
      ["+1246", "Barbados"],
      ["+375",  "Belarus"],
      ["+32",   "Belgium"],
      ["+501",  "Belize"],
      ["+229",  "Benin"],
      ["+1441", "Bermuda"],
      ["+975",  "Bhutan"],
      ["+591",  "Bolivia"],
      ["+387",  "Bosnia and Herzegovina"],
      ["+267",  "Botswana"],
      ["+55",   "Brazil"],
      ["+673",  "Brunei"],
      ["+359",  "Bulgaria"],
      ["+226",  "Burkina Faso"],
      ["+257",  "Burundi"],
      ["+855",  "Cambodia"],
      ["+237",  "Cameroon"],
      ["+1",    "Canada"],
      ["+3491", "Canary Islands"],
      ["+238",  "Cape Verde"],
      ["+1345", "Cayman Islands"],
      ["+236",  "Central Africa"],
      ["+235",  "Chad"],
      ["+56",   "Chile"],
      ["+86",   "China"],
      ["+61",   "Christmas Island"],
      ["+61",   "Cocos"],
      ["+57",   "Colombia"],
      ["+269",  "Comoros"],
      ["+242",  "Congo"],
      ["+243",  "Congo, Dem Rep"],
      ["+506",  "Costa Rica"],
      ["+385",  "Croatia"],
      ["+357",  "Cyprus"],
      ["+420",  "Czech Republic"],
      ["+45",   "Denmark"],
      ["+253",  "Djibouti"],
      ["+1767", "Dominica"],
      ["+1",    "Dominican Republic"],
      ["+593",  "Ecuador"],
      ["+20",   "Egypt"],
      ["+503",  "El Salvador"],
      ["+240",  "Equatorial Guinea"],
      ["+291",  "Eritrea"],
      ["+372",  "Estonia"],
      ["+251",  "Ethiopia"],
      ["+298",  "Faroe Islands"],
      ["+679",  "Fiji"],
      ["+358",  "Finland/Aland Islands"],
      ["+33",   "France"],
      ["+594",  "French Guiana"],
      ["+689",  "French Polynesia"],
      ["+241",  "Gabon"],
      ["+220",  "Gambia"],
      ["+995",  "Georgia"],
      ["+49",   "Germany"],
      ["+233",  "Ghana"],
      ["+350",  "Gibraltar"],
      ["+30",   "Greece"],
      ["+299",  "Greenland"],
      ["+1473", "Grenada"],
      ["+590",  "Guadeloupe"],
      ["+1671", "Guam"],
      ["+502",  "Guatemala"],
      ["+224",  "Guinea"],
      ["+592",  "Guyana"],
      ["+509",  "Haiti"],
      ["+504",  "Honduras"],
      ["+852",  "Hong Kong"],
      ["+36",   "Hungary"],
      ["+354",  "Iceland"],
      ["+91",   "India"],
      ["+62",   "Indonesia"],
      ["+98",   "Iran"],
      ["+964",  "Iraq"],
      ["+353",  "Ireland"],
      ["+972",  "Israel"],
      ["+39",   "Italy"],
      ["+225",  "Ivory Coast"],
      ["+1876", "Jamaica"],
      ["+81",   "Japan"],
      ["+962",  "Jordan"],
      ["+7",    "Kazakhstan"],
      ["+254",  "Kenya"],
      ["+850",  "Korea Dem People's Rep"],
      ["+883",  "Kosovo"],
      ["+965",  "Kuwait"],
      ["+996",  "Kyrgyzstan"],
      ["+856",  "Laos PDR"],
      ["+371",  "Latvia"],
      ["+961",  "Lebanon"],
      ["+266",  "Lesotho"],
      ["+231",  "Liberia"],
      ["+218",  "Libya"],
      ["+423",  "Liechtenstein"],
      ["+370",  "Lithuania"],
      ["+352",  "Luxembourg"],
      ["+853",  "Macau"],
      ["+389",  "Macedonia"],
      ["+261",  "Madagascar"],
      ["+265",  "Malawi"],
      ["+60",   "Malaysia"],
      ["+960",  "Maldives"],
      ["+223",  "Mali"],
      ["+356",  "Malta"],
      ["+692",  "Marshall Islands"],
      ["+596",  "Martinique"],
      ["+222",  "Mauritania"],
      ["+230",  "Mauritius"],
      ["+262",  "Mayotte"],
      ["+52",   "Mexico"],
      ["+691",  "Micronesia"],
      ["+373",  "Moldova"],
      ["+377",  "Monaco"],
      ["+976",  "Mongolia"],
      ["+382",  "Montenegro"],
      ["+1664", "Montserrat"],
      ["+212",  "Morocco/Western Sahara"],
      ["+258",  "Mozambique"],
      ["+95",   "Myanmar"],
      ["+264",  "Namibia"],
      ["+977",  "Nepal"],
      ["+31",   "Netherlands"],
      ["+599",  "Netherlands Antilles"],
      ["+687",  "New Caledonia"],
      ["+64",   "New Zealand"],
      ["+505",  "Nicaragua"],
      ["+227",  "Niger"],
      ["+234",  "Nigeria"],
      ["+1670", "Northern Mariana Islands"],
      ["+47",   "Norway"],
      ["+968",  "Oman"],
      ["+92",   "Pakistan"],
      ["+680",  "Palau"],
      ["+970",  "Palestinian Territory"],
      ["+507",  "Panama"],
      ["+595",  "Paraguay"],
      ["+51",   "Peru"],
      ["+63",   "Philippines"],
      ["+48",   "Poland"],
      ["+351",  "Portugal"],
      ["+1787", "Puerto Rico"],
      ["+974",  "Qatar"],
      ["+262",  "Reunion"],
      ["+40",   "Romania"],
      ["+7",    "Russia"],
      ["+250",  "Rwanda"],
      ["+685",  "Samoa"],
      ["+378",  "San Marino"],
      ["+966",  "Saudi Arabia"],
      ["+221",  "Senegal"],
      ["+381",  "Serbia"],
      ["+248",  "Seychelles"],
      ["+232",  "Sierra Leone"],
      ["+65",   "Singapore"],
      ["+421",  "Slovakia"],
      ["+386",  "Slovenia"],
      ["+252",  "Somalia"],
      ["+27",   "South Africa"],
      ["+82",   "South Korea"],
      ["+34",   "Spain"],
      ["+94",   "Sri Lanka"],
      ["+1869", "St Kitts and Nevis"],
      ["+1758", "St Lucia"],
      ["+508",  "St Pierre and Miquelon"],
      ["+1784", "St Vincent Grenadines"],
      ["+249",  "Sudan"],
      ["+597",  "Suriname"],
      ["+268",  "Swaziland"],
      ["+46",   "Sweden"],
      ["+41",   "Switzerland"],
      ["+963",  "Syria"],
      ["+886",  "Taiwan"],
      ["+992",  "Tajikistan"],
      ["+255",  "Tanzania"],
      ["+66",   "Thailand"],
      ["+228",  "Togo"],
      ["+676",  "Tonga"],
      ["+1868", "Trinidad and Tobago"],
      ["+216",  "Tunisia"],
      ["+90",   "Türkiye"],
      ["+90",   "Turkish Republic of Northern Cyprus"],
      ["+993",  "Turkmenistan"],
      ["+1649", "Turks and Caicos Islands"],
      ["+688",  "Tuvalu"],
      ["+256",  "Uganda"],
      ["+380",  "Ukraine"],
      ["+971",  "United Arab Emirates"],
      ["+44",   "United Kingdom"],
      ["+1",    "United States"],
      ["+598",  "Uruguay"],
      ["+998",  "Uzbekistan"],
      ["+379",  "Vatican City"],
      ["+58",   "Venezuela"],
      ["+84",   "Vietnam"],
      ["+1284", "Virgin Islands, British"],
      ["+1340", "Virgin Islands, U.S."],
      ["+967",  "Yemen"],
      ["+260",  "Zambia"],
      ["+263",  "Zimbabwe"],
    ]

    # A hash of country codes and names of countries that we support.
    # Based on previously available delivery rates. These are no longer
    # provided by Twilio
    SUPPORTED_COUNTRIES = [
      ["+358", "Aland Islands"],
      ["+213", "Algeria"],
      ["+244", "Angola"],
      ["+1264", "Anguilla"],
      ["+61", "Australia"],
      ["+43", "Austria"],
      ["+1", "Bahamas"],
      ["+973", "Bahrain"],
      ["+375", "Belarus"],
      ["+32", "Belgium"],
      ["+229", "Benin"],
      ["+591", "Bolivia"],
      ["+387", "Bosnia and Herzegovina"],
      ["+55", "Brazil"],
      ["+673", "Brunei"],
      ["+359", "Bulgaria"],
      ["+257", "Burundi"],
      ["+855", "Cambodia"],
      ["+1", "Canada"],
      ["+238", "Cape Verde"],
      ["+1345", "Cayman Islands"],
      ["+61", "Christmas Island"],
      ["+61", "Cocos"],
      ["+243", "Congo, Dem Rep"],
      ["+385", "Croatia"],
      ["+357", "Cyprus"],
      ["+420", "Czech Republic"],
      ["+45", "Denmark"],
      ["+1767", "Dominica"],
      ["+1", "Dominican Republic"],
      ["+593", "Ecuador"],
      ["+240", "Equatorial Guinea"],
      ["+372", "Estonia"],
      ["+358", "Finland/Aland Islands"],
      ["+33", "France"],
      ["+220", "Gambia"],
      ["+995", "Georgia"],
      ["+49", "Germany"],
      ["+233", "Ghana"],
      ["+350", "Gibraltar"],
      ["+30", "Greece"],
      ["+502", "Guatemala"],
      ["+592", "Guyana"],
      ["+36", "Hungary"],
      ["+354", "Iceland"],
      ["+91", "India"],
      ["+353", "Ireland"],
      ["+972", "Israel"],
      ["+39", "Italy"],
      ["+225", "Ivory Coast"],
      ["+1876", "Jamaica"],
      ["+81", "Japan"],
      ["+962", "Jordan"],
      ["+965", "Kuwait"],
      ["+371", "Latvia"],
      ["+218", "Libya"],
      ["+423", "Liechtenstein"],
      ["+370", "Lithuania"],
      ["+352", "Luxembourg"],
      ["+261", "Madagascar"],
      ["+265", "Malawi"],
      ["+60", "Malaysia"],
      ["+960", "Maldives"],
      ["+223", "Mali"],
      ["+356", "Malta"],
      ["+230", "Mauritius"],
      ["+52", "Mexico"],
      ["+377", "Monaco"],
      ["+382", "Montenegro"],
      ["+1664", "Montserrat"],
      ["+258", "Mozambique"],
      ["+264", "Namibia"],
      ["+31", "Netherlands"],
      ["+599", "Netherlands Antilles"],
      ["+64", "New Zealand"],
      ["+234", "Nigeria"],
      ["+47", "Norway"],
      ["+48", "Poland"],
      ["+351", "Portugal"],
      ["+974", "Qatar"],
      ["+40", "Romania"],
      ["+250", "Rwanda"],
      ["+221", "Senegal"],
      ["+381", "Serbia"],
      ["+248", "Seychelles"],
      ["+65", "Singapore"],
      ["+421", "Slovakia"],
      ["+386", "Slovenia"],
      ["+27", "South Africa"],
      ["+82", "South Korea"],
      ["+34", "Spain"],
      ["+94", "Sri Lanka"],
      ["+1758", "St Lucia"],
      ["+249", "Sudan"],
      ["+46", "Sweden"],
      ["+41", "Switzerland"],
      ["+886", "Taiwan"],
      ["+255", "Tanzania"],
      ["+228", "Togo"],
      ["+1868", "Trinidad and Tobago"],
      ["+1649", "Turks and Caicos Islands"],
      ["+256", "Uganda"],
      ["+971", "United Arab Emirates"],
      ["+44", "United Kingdom"],
      ["+1", "United States"],
      ["+598",  "Uruguay"],
      ["+58", "Venezuela"],
    ]

    # Hash of country codes =>  array[code, name] for countries that we don't support.
    UNSUPPORTED_COUNTRY_CODES = COUNTRY_CODES.dup.each_with_object({}) do |pair, hsh|
      unless SUPPORTED_COUNTRIES.include? pair
        hsh[pair.first] ||= []
        hsh[pair.first] << [pair.first, pair.last]
      end
    end

    extend self
  end
end
