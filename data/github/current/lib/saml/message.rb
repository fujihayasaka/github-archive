# typed: true
# frozen_string_literal: true

require "base64"
require "uri"
require "nokogiri"
require "zlib"
require "tempfile"

module SAML
  # Abstract base class for SAML XML documents.
  class Message
    SCHEMA_DIR = File.expand_path("../schemas", __FILE__)

    class SigningError < RuntimeError; end

    # Internal: Hash of concrete implementations of Message keyed by class name
    def self.subclasses
      @subclasses ||= {}
    end

    # Internal: Keep track of subclasses
    def self.inherited(klass)
      subclasses[klass.name.split("::").last] = klass
    end

    # Public: Initializes a concrete assertion subclass with a
    # Nokogiri::XML::Document instance wrapping `xml`. See .parse_query for
    # instantiating compressed and base64 encoded messages.
    #
    # Returns SAML::Message instance
    def self.build(xml, options = {})
      if GitHub.enterprise? && GitHub.saml_encrypted_assertions?
        doc = Nokogiri::XML(xml)
        doc = Nokogiri::XML("<unknown />") unless doc.root

        # Unknown messages are instantiated the current class. This allows unknown
        # messages to still follow the same contract as other concrete messages.
        message_name = doc.root.name
        message_class = subclasses.fetch(message_name, self)

        # Search for signatures on the root of the document, given that signatures in an encrypted assertion will not
        # be found until the assertion is decrypted.
        signatures = message_class.signatures(doc)

        # Only take the signatures that belong to the root of the document, and have a matching reference URI on the
        # `Response` node.
        signatures = signatures.filter do |signature|
          sig_node = signature.signature

          response_node = sig_node.parent

          # Signature needs to be a direct child of the `Response` node
          next false unless response_node && response_node&.name == "Response"

          response_parent_node = response_node&.parent

          # Response node should be wrapped in the Nokogiri document node, which indicates that it is
          # positioned at the root of the document.
          next false unless response_parent_node && response_parent_node&.document?

          ref = sig_node.at_xpath(
            "./ds:SignedInfo/ds:Reference",
            Xmldsig::NAMESPACES,
          )

          # ref node needs to exist
          next false unless ref

          # trim off leading '#' symbol
          trimmed_ref = String(String(ref["URI"])[1..-1])

          # and ensure it contains content using the same check as `has_root_sig_and_matching_ref?` and
          # `all_assertions_signed_with_matching_ref` in response.rb
          next false unless trimmed_ref.length > 1

          # ensure it matches the ID of the `Response` node
          trimmed_ref == String(doc.root["ID"])
        end

        decrypt_errors = []
        plain_doc = message_class.decrypt(doc, options, decrypt_errors)

        # Search for signatures in the decrypted document, which will include assertion signatures now. Note that this
        # will re-find any signatures filtered out above. This is OK because we now know that we'll also pick up the
        # actual assertion signatures for validation, which will prevent tampering.
        signatures = message_class.signatures(plain_doc) if signatures.empty?

        message = message_class.parse(plain_doc, signatures)
        message.errors.concat(decrypt_errors)
        message.errors.each { |e| GitHub::Authentication.logger.error("exception.message" => e) }
        message
      else
        doc = Nokogiri::XML(xml)
        doc = Nokogiri::XML("<unknown />") unless doc.root

        # Unknown messages are instantiated the current class. This allows unknown
        # messages to still follow the same contract as other concrete messages.
        message_name = doc.root.name
        message_class = subclasses.fetch(message_name, self)

        # Query the signatures from the XML document before possible decryption
        signatures = message_class.signatures(doc)

        decrypt_errors = []
        plain_doc = message_class.decrypt(doc, options, decrypt_errors)

        message = message_class.parse(plain_doc, signatures)
        message.errors.concat(decrypt_errors)
        message.errors.each { |e| GitHub::Authentication.logger.error("exception.message" => e) }
        message
      end
    end

    # Public: Base64 decodes encoded and builds a concrete subclass instance.
    # Complement to #to_param.
    #
    # Returns SAML::Message instance
    def self.from_param(encoded, options = {})
      raise "nil SAML response" if encoded.nil?

      begin
        decoded = Base64.decode64(encoded)
        build(decoded, options)
      rescue => e
        raise "Failed to decode SAML response - #{e.message}"
      end
    end

    # Public: Returns Nokogiri::XML::Document for SAML message encoded for
    # Redirect profile.
    def self.decode_query(query)
      decoded = Base64.decode64(query)
      Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(decoded)
    end

    # Public: The complement to #to_query. Caller is responsible for unescaping
    # `query`.
    #
    # Returns SAML::Message instance
    def self.from_query(query)
      decoded = decode_query(query)
      build(decoded)
    end

    # Internal: Returns a list of Xmldsig::Signature objects in `document`. Used
    # for signing documents and validating signatures.
    #
    # Returns an array of Xmldsig::Signature objects
    def self.signatures(doc)
      signatures = doc.xpath("//ds:Signature", Xmldsig::NAMESPACES)
      signatures.reverse.collect do |node|
        Xmldsig::Signature.new(node)
      end || []
    end

    # Internal: Override this method for custom decryption (by default no
    # decryption of the document is performed). `doc` is an
    # instance of Nokogiri::XML::Document. `doc` is decrypted in place.
    #
    # Will throw an exception if decryption fails.
    def self.decrypt(doc, options, errors)
      doc
    end

    # Internal: Override this method for custom initialization. `doc` is an
    # instance of Nokogiri::XML::Document.
    #
    # Returns Message subclass instance
    #
    # TODO: figure out a way to have parse happen after schema validation. Doing
    # duplicate work checking for null values in document during parsing.
    def self.parse(doc, signatures = nil)
      message = new
      message.document = doc
      message.signatures = signatures
      message
    end

    # Public:
    #
    # Note: An abstract Message class may be instantiated if an unknown SAML
    # message is encountered. The instance follows the same contract, but will
    # be invalid because it will not pass schema validation.
    def initialize(options = {})
      options.each do |k, v|
        ivar = "@#{k}"
        instance_variable_set ivar, v
      end
    end

    # Public: Returns base64 encoded xml for POST bindings
    def to_param
      Base64.strict_encode64(to_xml)
    end

    # Public: Returns compressed, base64 encoded query parameter of this
    # assertion for redirect bindings. Caller is responsible for URL encoding
    # the parameter.
    def to_query
      deflated = Zlib::Deflate.deflate(to_s, 9)[2..-5]
      Base64.strict_encode64(deflated)
    end

    # Public: Two messages are equal if their XML strings are equal
    def ==(other)
      other.document.to_xml == document.to_xml
    end

    # Public: Method to get the xml document representing this SAML
    # object. If encrypted assertions are being used, then this
    # document contains the plain text assertion.
    #
    # Returns Nokogiri::XML::Document instance representing this assertion.
    def document
      @document ||= build_document
    end
    attr_writer :document

    # Public: Method to get the signatures representing the SAML object
    # as we got it from the IdP. This is relevant if the document contained
    # encrypted assertions, because then these signatures are calculated
    # based on these encrypted assertions and not based on their plain text
    # counterparts in `document`.
    #
    # Returns Nokogiri::XML::Document instance representing this assertion.
    def signatures
      @signatures ||= []
    end
    attr_writer :signatures

    # Public: Returns array of validation errors
    def errors
      @errors ||= []
    end
    attr_writer :errors

    # Public: Sign all signatures in `document`. Returns nothing.
    #
    # :private_key - OpenSSL::PKey::RSA instance
    # :certificate - optional OpenSSL::X509::Certificate instance. Embeds
    #                certificate into KeyInfo.
    def sign(options = {})
      unless options[:private_key]
        raise ArgumentError.new("Missing :private_key")
      end

      document.xpath("//ds:Signature", Xmldsig::NAMESPACES).reverse_each do |element|
        signature = Xmldsig::Signature.new(element)

        # add ds:X509Certificate
        if options[:certificate]
          encoded_certificate = Base64.strict_encode64(options[:certificate].to_s).chomp

          keyinfo = Nokogiri::XML::Node.new("ds:KeyInfo", document)
          x509Data = Nokogiri::XML::Node.new("ds:X509Data", document)
          x509certificate = Nokogiri::XML::Node.new("ds:X509Certificate", document)

          x509Data << x509certificate
          keyinfo << x509Data
          signature.signature << keyinfo

          signature.signature.at_xpath("descendant::ds:X509Certificate", Xmldsig::NAMESPACES).content = encoded_certificate
        end

        # add ds:SignatureValue
        signature.sign(options[:private_key])
      end
    end

    # Returns XML string of internal `document`. Whitespace is preserved because
    # XML hash digests would not match otherwise.
    def to_xml(_options = {})
      document.to_xml(save_with: 0)
    end

    def to_s
      to_xml
    end

    def inspect
      to_s
    end

    # Public: Validates schema and custom validations.
    #
    # Returns false if we detected a parsing error or if instance is invalid. #errors will be non-empty in that case.
    def valid?(options = {})
      errors.clear
      return false if errors.any?

      validate_schema && validate(options)
      errors.empty?
    end

    private

    # Private: Override this method to add subclass specific validations. See
    # #valid? for public interface.
    #
    # Returns boolean whether assertion is valid
    def validate(options)
      true
    end

    # Private: builds a xml document
    # subclasses are expected to implement this method.
    #
    # Returns a nokogiri xml document
    def build_document
      raise NotImplementedError
    end

    # Private: Returns string with saml formatted time
    def format_time(t)
      t.to_time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    end

    # Private: Returns false if `document` is invalid SAML xml
    def validate_schema
      # Reason we don't memoize this is because nokogiri needs the relative
      # paths to find the other schema definitions.
      Dir.chdir(SCHEMA_DIR) do
        schema = Nokogiri::XML::Schema(File.read("saml20protocol_schema.xsd"))
        self.errors += schema.validate(document)
      end
    end
  end
end
