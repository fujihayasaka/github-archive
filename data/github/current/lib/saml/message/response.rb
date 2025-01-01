# typed: false
# frozen_string_literal: true

require "forwardable"
require "active_support/core_ext/module/delegation"
require "xmldsig"

module SAML
  class Message
    class AssertionDecryptionHelper

      class EncryptedAssertionError < StandardError
      end

      def initialize(options, errors = nil)
        @key = options[:key]
        @errors = errors

        @namespaces = {
          "ds"   => "http://www.w3.org/2000/09/xmldsig#",
          "xenc" => "http://www.w3.org/2001/04/xmlenc#",
        }

        # Maps the algorithm names from XMLENC to the corresponding OpenSSL
        # algorithm name and block size
        @xmlenc2algo = {
          "#{@namespaces["xenc"]}aes128-cbc"     => { name: "aes-128-cbc", key_size: 128 },
          "#{@namespaces["xenc"]}aes192-cbc"     => { name: "aes-192-cbc", key_size: 192 },
          "#{@namespaces["xenc"]}aes256-cbc"     => { name: "aes-256-cbc", key_size: 256 },
          "#{@namespaces["xenc"]}rsa-oaep-mgf1p" => { name: "rsa-oaep"   , padding: OpenSSL::PKey::RSA::PKCS1_OAEP_PADDING },
        }

        # This class accepts the XMLENC algorithm name as well as the OpenSSL
        # algorithm name. However, if we detect an XMLENC name then we normalize
        # it to the OpenSSL name
        @key_transport_method = options[:key_transport_method]
        if @xmlenc2algo.key?(@key_transport_method)
          @key_transport_method = @xmlenc2algo[@key_transport_method][:name]
        end

        @encryption_method = options[:encryption_method]
        if @xmlenc2algo.key?(@encryption_method)
          @encryption_method = @xmlenc2algo[@encryption_method][:name]
        end

      end

      # Returns array of decryption errors
      def errors
        @errors ||= []
      end
      attr_writer :errors

      def decrypt(node)
        return if node.nil?
        decrypted_assertion = decrypt_assertion(node)
        node.replace(decrypted_assertion)
      rescue EncryptedAssertionError => e
        self.errors << "GitHub SAML #{e}"
      rescue OpenSSL::PKey::RSAError => e
        self.errors << "GitHub was not able to decrypt SAML assertions. Is the IDP using the wrong certificate?"
      end

      # Remove the padding from decrypted assertions
      # The last byte of the decrypted data defines the length of the padding (including the last byte which is part
      # of the padding).
      # See: https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-Block
      def remove_padding(data, block_size)
        padding = data[-1].bytes[0]
        if padding < 1
          raise EncryptedAssertionError.new "expected padding greater than 0 but got #{padding}"
        elsif padding > block_size
          raise EncryptedAssertionError.new "expected padding smaller than #{block_size} but got #{padding}"
        end
        data[0...-padding]
      end

      private

      def algorithm(enc_assert_node)
        xmlenc_algo = enc_assert_node.at_xpath("./xenc:EncryptionMethod/@Algorithm", @namespaces).value
        @xmlenc2algo.fetch(xmlenc_algo, { name: "unknown" })
      end

      def cipher_key(node)
        enc_key_node = node.at_xpath("./xenc:EncryptedData/ds:KeyInfo/xenc:EncryptedKey", @namespaces)
        if !enc_key_node
          cipher_uri    = node.at_xpath("./xenc:EncryptedData/ds:KeyInfo/ds:RetrievalMethod/@URI", @namespaces).value.delete_prefix("#")
          enc_key_node  = node.at_xpath("./xenc:EncryptedKey[@Id='#{cipher_uri}']", @namespaces)
        end

        key_transport = algorithm(enc_key_node)
        if key_transport[:name] != @key_transport_method
          raise EncryptedAssertionError.new "expected #{@key_transport_method.upcase} as key transport method for encrypted assertions but got #{key_transport[:name].upcase}"
        end

        cipher_base64 = enc_key_node.at_xpath("./xenc:CipherData/xenc:CipherValue", @namespaces).text
        cipher        = Base64.decode64(cipher_base64)

        raise EncryptedAssertionError.new "is missing private key" if @key.nil?
        @key.private_decrypt(cipher, key_transport[:padding])
      end

      def data(node)
        data_base64 = node.at_xpath("./xenc:EncryptedData/xenc:CipherData/xenc:CipherValue", @namespaces).text
        Base64.decode64(data_base64)
      end

      # See: https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Processing-Decryption
      def decrypt_assertion(node)
        encryption = algorithm(node.at_xpath("./xenc:EncryptedData", @namespaces))
        if encryption[:name] != @encryption_method
          raise EncryptedAssertionError.new "expected #{@encryption_method.upcase} as algorithm for encrypted assertions but got #{encryption[:name].upcase}"
        end

        key  = cipher_key(node)
        data = data(node)

        # For AES CBC the first 128 bit of the data are the IV and the remaining
        # bits are the actual cipher text
        # See https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-Block
        iv = data[0..15]
        cipher_text = data[16..-1]

        decipher = OpenSSL::Cipher.new(encryption[:name])
        decipher.decrypt
        decipher.padding = 0
        decipher.key = key
        decipher.iv = iv

        plain_data = decipher.update(cipher_text) + decipher.final
        remove_padding(plain_data, decipher.block_size)
      end

    end

    # This class represents a SAML Response. It currently wraps around
    # ruby-saml's Onelogin::SAML::Response class, but gives an interface
    # consistent with the rest of our SAML classes.
    #
    # [4.1.4.2 <Response> Usage](http://docs.oasis-open.org/security/saml/v2.0/saml-profiles-2.0-os.pdf)
    # [3.2 Requests and Responses](http://docs.oasis-open.org/security/saml/v2.0/saml-core-2.0-os.pdf)
    # [Schema](http://www.schemacentral.com/sc/saml2/e-samlp_Response.html)
    #
    class Response < Message
      include Scientist
      include SAML::Shared::Issuer
      include SAML::Shared::Status
      include SAML::Shared::Response

      attr_accessor :name_id             # String principal of the assertion
      attr_accessor :name_id_format      # Format of NameID assertion
      attr_accessor :subject             # Subject element of IdP Response
      attr_accessor :session_expires_at  # UTC time of session expiration
      attr_accessor :session_index       # SessionIndex for single logout
      attr_accessor :status_message

      def self.decrypt(doc, options, errors)
        return doc unless options && !!options[:encrypted_assertions]

        dup_doc = doc.dup
        node = dup_doc.at_xpath("/saml2p:Response/saml2:EncryptedAssertion", namespaces)
        if node
          AssertionDecryptionHelper.new(options, errors).decrypt(node)
        else
          errors << "GitHub expected SAML encrypted assertions but none found"
          # Encrypted assertions are enabled here. However, we did not find one.
          # Let's remove potentially existing unencrypted assertions to provoke
          # an error.
          dup_doc.xpath("/saml2p:Response/saml2:Assertion", namespaces).each do |assertion|
            assertion.remove
          end
        end
        dup_doc
      end

      def self.parse(doc, signatures = nil)
        d = doc.dup

        sig_nodes = d.xpath("//ds:Signature", namespaces)

        # remove Signature nodes to avoid pulling data from them
        # see: https://github.com/github/github/issues/67357#issuecomment-273664368
        # for details on how this can be exploited
        if sig_nodes && !sig_nodes.empty?
          sig_nodes.each do |sig_node|
            sig_node.remove
          end
        end

        destination = d.root.attr("Destination")

        # issuer can be either in the root response element or under the assertion itself.
        issuer = d.at_xpath("/saml2p:Response/saml2:Issuer", namespaces) && d.at_xpath("/saml2p:Response/saml2:Issuer", namespaces).text
        issuer ||= d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Issuer", namespaces) && d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Issuer", namespaces).text

        status_code = d.at_xpath("/saml2p:Response/saml2p:Status/saml2p:StatusCode", namespaces)
        status_code = status_code && status_code.attr("Value")

        # Second-level status codes are optional. These give more context in case of a failed AuthnRequest,
        # such as AuthnFailed or RequestDenied.
        #
        # See: https://docs.oasis-open.org/security/saml/v2.0/saml-core-2.0-os.pdf, sections 3.2.2.1 to 3.2.2.4
        #
        # Example of a second-level status code, nested in a top-level status code:
        #
        # <samlp:Status>
        #   <samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:Responder">
        #     <samlp:StatusCode Value="urn:oasis:names:tc:SAML:2.0:status:RequestDenied"/>
        #   </samlp:StatusCode>
        # </samlp:Status>
        #
        second_level_status_code = d.at_xpath("/saml2p:Response/saml2p:Status/saml2p:StatusCode/saml2p:StatusCode", namespaces)
        second_level_status_code = second_level_status_code && second_level_status_code.attr("Value")

        status_message = d.at_xpath("/saml2p:Response/saml2p:Status/saml2p:StatusMessage", namespaces)
        status_message = status_message && status_message.text

        authn = d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:AuthnStatement", namespaces)

        expiry = authn && authn["SessionNotOnOrAfter"]
        expiry = expiry && Time.parse(expiry + " UTC")

        session_index = authn && authn["SessionIndex"]

        # TODO: this belongs in Assertion
        conditions = d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Conditions", namespaces)
        not_before = conditions && conditions["NotBefore"]
        not_before = not_before && Time.parse(not_before + " UTC")
        not_on_or_after = conditions && conditions["NotOnOrAfter"]
        not_on_or_after = not_on_or_after && Time.parse(not_on_or_after + " UTC")
        audience_text = d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Conditions/saml2:AudienceRestriction", namespaces) && d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Conditions/saml2:AudienceRestriction/saml2:Audience", namespaces) && d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Conditions/saml2:AudienceRestriction/saml2:Audience", namespaces).text

        # TODO: this belongs in Assertion
        attribute_statements = d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:AttributeStatement", namespaces)
        attributes = attribute_statements && attribute_statements.xpath("saml2:Attribute", namespaces).inject({}) do |attrs, attribute|
          # Name is required, FriendlyName is optional. We'll use either though.
          name = attribute["Name"]
          friendly_name = attribute["FriendlyName"]
          values = attribute.xpath("saml2:AttributeValue", namespaces).map do |attribute_value|
            attribute_value.text
          end
          attrs[name] = attrs[name.to_sym] = values
          if friendly_name
            attrs[friendly_name] = attrs[friendly_name.to_sym] = values
          end
          attrs
        end

        subject = d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Subject", namespaces) && d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Subject", namespaces).text
        name_id = d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Subject/saml2:NameID", namespaces) && d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Subject/saml2:NameID", namespaces).text
        name_id_format = d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Subject/saml2:NameID", namespaces) && d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Subject/saml2:NameID", namespaces)["Format"]

        subj_conf_data = d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Subject/saml2:SubjectConfirmation", namespaces) && d.at_xpath("/saml2p:Response/saml2:Assertion/saml2:Subject/saml2:SubjectConfirmation/saml2:SubjectConfirmationData", namespaces)
        recipient_attr = subj_conf_data && subj_conf_data["Recipient"]
        in_response_to_attr = subj_conf_data && subj_conf_data["InResponseTo"]

        errors = []

        # if we have both InResponseTo on the root element and on the SubjectConfirmationData element make sure they match.
        if in_response_to_attr && d.root.attr("InResponseTo") && d.root.attr("InResponseTo") != in_response_to_attr
          errors << "InResponseTo value on the Response element doesn't match the InResponseTo value in the SubjectConfirmationData element."
        end

        new({
          destination: destination,
          name_id: name_id,
          name_id_format: name_id_format || "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified",
          subject: subject,
          issuer: issuer,
          in_response_to: in_response_to_attr || d.root.attr("InResponseTo"),
          recipient: recipient_attr,
          audience: audience_text,
          session_expires_at: expiry,
          session_index: session_index,
          status_code: status_code,
          second_level_status_code: second_level_status_code,
          status_message: status_message,
          not_before: not_before,
          not_on_or_after: not_on_or_after,
          attributes: attributes,
          document: doc,
          signatures: signatures,
          errors: errors,
        })
      end

      def build_document(include_sig_template: false)
        # This is to maintain compatibility with delegating parsing to ruby-saml
        # for the time being. When we decide to full implement .parse, we'll be
        # able to remove this.
        return @document if @document

        doc = Nokogiri::XML::Builder.new do |xml|
          root_attributes = {
            "xmlns:samlp"     => "urn:oasis:names:tc:SAML:2.0:protocol",
            "xmlns:saml"      => "urn:oasis:names:tc:SAML:2.0:assertion",
            "xmlns:ds"        =>  "http://www.w3.org/2000/09/xmldsig#",
            "ID"              => id,
            "IssueInstant"    => format_time(issue_instant),
            "Version"         => version,
          }
          root_attributes["Destination"]  = destination    if destination.present?
          root_attributes["InResponseTo"] = in_response_to if in_response_to.present?

          xml.Response(root_attributes) do
            # hack b/c nokogiri 1.5.6 doesn't evaluate ns definitions first
            xml.parent.namespace = xml.parent.namespace_definitions.first

            generate_issuer(xml)

            xml_signature_template(xml, id) if include_sig_template

            generate_status(xml)

            # Assertions match up with ruby-saml response functionality for now.
            if @attributes # ivar means they were set instead of read from docment
              assertion = Assertion.new({
                attributes: @attributes,
                issuer: issuer,
                name_id: name_id,
                name_id_format: name_id_format,
                recipient: recipient,
                audience: audience,
              })
              assertion.decorate(xml)
            end
          end
        end.doc

        @document = doc
        @document
      end

      # inserts a signature, usually after issuer, that looks like:
      # <ds:Signature>
      # <ds:SignedInfo>
      #   <ds:CanonicalizationMethod Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#"/>
      #   <ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#rsa-sha256"/>
      #   <ds:Reference URI="#foo">
      #     <ds:Transforms>
      #       <ds:Transform Algorithm="http://www.w3.org/2000/09/xmldsig#enveloped-signature"/>
      #       <ds:Transform Algorithm="http://www.w3.org/2001/10/xml-exc-c14n#">
      #       </ds:Transform>
      #     </ds:Transforms>
      #     <ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/>
      #     <ds:DigestValue></ds:DigestValue>
      #   </ds:Reference>
      # </ds:SignedInfo>
      # <ds:SignatureValue></ds:SignatureValue>
      # </ds:Signature>
      def xml_signature_template(builder, uri)
        builder["ds"].Signature do |builder|
          builder.SignedInfo do |builder|
            builder.CanonicalizationMethod(Algorithm: "http://www.w3.org/2001/10/xml-exc-c14n#")
            builder.SignatureMethod(Algorithm: "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256")
            builder.Reference(URI: "#" + String(uri)) do |builder|
              builder.Transforms do |builder|
                builder.Transform(Algorithm: "http://www.w3.org/2000/09/xmldsig#enveloped-signature")
                builder.Transform(Algorithm: "http://www.w3.org/2001/10/xml-exc-c14n#")
              end
              builder.DigestMethod(Algorithm: "http://www.w3.org/2001/04/xmlenc#sha256")
              builder.DigestValue
            end
          end
          builder.SignatureValue
        end
      end

      def validate(options)
        if GitHub.flipper[:fail_saml_response_with_dtd].enabled? || GitHub.enterprise?
          validate_no_dtd
        end

        if !SAML.mocked[:skip_validate_signature]
          validate_has_signature
          validate_certificate(options[:idp_certificate]) if certificate_expiration_check_enabled?

          validate_assertion_digest_values

          if GitHub.enterprise? && GitHub.saml_encrypted_assertions?
            validate_signatures_ghes(options[:idp_certificate])
          else
            validate_signatures(options[:idp_certificate])
          end

          # Stop validation early when signature validation fails
          return if self.errors.any?
        end
        validate_has_assertion unless SAML.mocked[:skip_validate_has_assertion]
        validate_issuer(options[:issuer])
        validate_destination(options[:sp_url])
        validate_recipient(options[:sp_url])
        validate_conditions
        validate_audience(audience_url(options[:sp_url]))
        validate_name_id_format(options[:name_id_format])
        validate_administrator(options[:require_admin])

        has_multiple_assertions = document.xpath("//saml2:Assertion", namespaces).count > 1
        has_errors = !self.errors.empty?
        has_root_sig = has_root_sig_and_matching_ref?

        GitHub.dogstats.increment(
          "external_identities.saml.assertions",
          tags: [
            "has_multiple_assertions:#{has_multiple_assertions}",
            "has_errors:#{has_errors}",
            "has_root_sig:#{has_root_sig}"
          ]
        )
      end

      # Internal: Validate that the SAML response does not contain a DOCTYPE declaration.
      def validate_no_dtd
        GitHub.logger.info(
          "Running validate_no_dtd",
          "saml.internal_subset" => document.internal_subset.present?,
        )

        if document.internal_subset.present?
          self.errors << "SAML Response includes a document type declaration. Please adjust the response to remove it and try again."
        end
      end

      # Internal: Validate the issuer of the message if present in configuration.
      # We don't require one to be configured since the admin may not know the
      # appropriate value to use; nil and "" allow any issuer.
      def validate_issuer(expected)
        return if SAML.mocked[:skip_issuer] || !expected || expected.empty?
        if String(issuer) != expected
          self.errors << "Issuer is invalid."
        end
      end

      # Internal: Validate the audience of the message. Should always be
      # the dotcom or enterprise url (our EntityID)
      def validate_audience(sp_url)
        error = audience_validation(sp_url)
        if error
          self.errors << error
        end
      end

      # internal: for debugging purposes, this dumps the response's XML in a way
      # that we can securely log it
      def dump_xml_without_signature
        doc_copy = self.document.dup
        if sig = doc_copy.xpath("//ds:Signature", namespaces)
          sig.remove
        end
        doc_copy.to_xml(indent: 2)
      end

      # Error will be reported if audience is missing or distinct from sp_url
      # This is the new compliant logic to validate audience
      def audience_validation(sp_url)
        return if SAML.mocked[:skip_audience]
        if !audience || audience.downcase != sp_url&.downcase
          "Audience is invalid. Audience attribute does not match #{sp_url}"
        end
      end

      # Internal: Validate the format of the NameId field
      def validate_name_id_format(specified_format)
        return unless specified_format
        return if SAML.mocked[:skip_name_id_format]

        if name_id_format && name_id_format != specified_format
          self.errors << "NameID format must be '#{ specified_format }'."
          nil
        end
      end

      # Internal: Validate the recipient of the message. Should always be
      # the doctom or enterprise url followed by /saml/consume or /saml/validate.
      #
      # If no Subject element is present, no assertion is being made, no
      # SubjectConfirmationData element will be present, and therefore
      # no recipient. In these cases we do not require a recipient.
      #
      # For instance, this is the case when a 'RequestDenied' second-level
      # status code is sent. This sometimes indicates that the IdP has not
      # authorized the user for the SP (GitHub).
      #
      # See: https://github.com/github/github/pull/56870
      #
      def validate_recipient(sp_url)
        return if !subject
        return if SAML.mocked[:skip_destination]
        if !recipient
          self.errors << "Recipient in the SAML response must not be blank."
          return
        end
        if recipient.downcase != "#{sp_url&.downcase}/saml/consume" && recipient != "#{sp_url&.downcase}/saml/validate"
          self.errors << "Recipient in the SAML response was not valid."
          nil
        end
      end

      # Internal: Validate the destination of the message.
      # MUST be present if SAML message itself is signed
      # If present MUST have
      # `_host_/saml/consume` as its value
      #
      # https://docs.oasis-open.org/security/saml/v2.0/saml-bindings-2.0-os.pdf
      #
      # 3.5.5.2
      #
      # If the message is signed, the Destination XML attribute in the root SAML
      # element of the protocol message MUST contain the URL to which the sender
      # has instructed the user agent to deliver the message. The recipient MUST
      # then verify that the value matches the location at which the message has
      # been received.
      #
      # From the above one infers destination is only required when the message
      # (the root document) is signed. If instead only the assertion was signed, it
      # wouldn't be necessary as per spec.
      #
      def validate_destination(sp_url)
        return if SAML.mocked[:skip_destination]
        # destination is only required when the message is signed, not the assertion
        return unless has_root_sig_and_matching_ref?
        unless destination && destination.downcase == "#{sp_url&.downcase}/saml/consume"
          self.errors << "Destination in the SAML response was not valid."
          nil
        end
      end

      # Internal: Validate that the SAML message (root XML element of SAML response)
      # or all contained assertions are signed
      #
      # Verification of signatures is done in #validate_signatures
      def validate_has_signature
        # Return early if entire response is signed. This prevents individual
        # assertions from being tampered because any change in the response
        # would invalidate the entire response.
        return if has_root_sig_and_matching_ref?
        return if all_assertions_signed_with_matching_ref?

        self.errors << "SAML Response is not signed or has been modified."
      end

      # Internal: Validate all XML signatures against `certificate`. Returns
      # boolean.
      def validate_signatures(raw_cert)
        unless raw_cert
          self.errors << "No Certificate"
          return
        end
        certificate = OpenSSL::X509::Certificate.new(raw_cert)
        unless signatures.all? { |signature| signature.valid?(certificate) }
          self.errors << "Digest mismatch"
        end
      rescue Xmldsig::SchemaError => e
        self.errors << "Invalid signature"
      rescue OpenSSL::X509::CertificateError => e
        self.errors << "Certificate error: '#{e.message}'"
      end

      # Internal: Validate all XML signatures against `certificate for GHES with encrypted assertion enabled.
      # Returns boolean.
      def validate_signatures_ghes(raw_cert)
        unless raw_cert
          self.errors << "No Certificate"
          return
        end

        unless signatures.any?
          self.errors << "No signatures found"
          return
        end

        certificate = OpenSSL::X509::Certificate.new(raw_cert)
        unless signatures.all? { |signature| signature.valid?(certificate) }
          self.errors << "Digest mismatch"
        end
      rescue Xmldsig::SchemaError => e
        self.errors << "Invalid signature"
      rescue OpenSSL::X509::CertificateError => e
        self.errors << "Certificate error: '#{e.message}'"
      end

      # Never run the certificate check for now
      def certificate_expiration_check_enabled?
        false
      end

      def validate_certificate(raw_cert)
        certificate = OpenSSL::X509::Certificate.new(raw_cert)
        expired_at = certificate.not_after
        if expired_at.to_i <= Time.now.to_i
          self.errors << "IdP signing certificate expired"
        end
      end

      def validate_has_assertion
        return if !document.at("/saml2p:Response/saml2:Assertion", namespaces).nil?
        self.errors << "No assertion found"
      end

      def has_root_sig_and_matching_ref?
        return true if SAML.mocked[:mock_root_sig]
        root_ref = document.at("/saml2p:Response/ds:Signature/ds:SignedInfo/ds:Reference", namespaces)
        return false unless root_ref
        root_ref_uri = String(String(root_ref["URI"])[1..-1]) # chop off leading #
        return false unless root_ref_uri.length > 1
        root_rep = document.at("/saml2p:Response", namespaces)
        root_id = String(root_rep["ID"])

        # and finally does the root ref URI match the root ID?
        root_ref_uri == root_id
      end

      def all_assertions_signed_with_matching_ref?
        assertions = document.xpath("//saml2:Assertion", namespaces)
        assertions.all? do |assertion|
          ref = assertion.at("./ds:Signature/ds:SignedInfo/ds:Reference", namespaces)
          return false unless ref
          assertion_id = String(assertion["ID"])
          ref_uri = String(String(ref["URI"])[1..-1]) # chop off leading #
          return false unless ref_uri.length > 1

          ref_uri == assertion_id
        end
      end

      # https://github.com/github/external-identities/issues/5191
      #
      # Xmldsig is responsible for validating all the signatures in the response. This currently happens in the
      # `validate_signatures` method below. This calls the `Xmldsign::Signature#valid?` method, which calls
      # `Xmldsig::Reference#validate_digest_value` to validate the digest.
      #
      # If we have multiple signatures with matching reference IDs, Xmldsig will attempt to validate all of them, but
      # when it calculates the digest for the node, it will only use the first reference it finds. Therefore, only the
      # first signature will be validated correctly.
      #
      # To correct this, we need to validate the digest for each signature against the assertion node itself to ensure
      # it has not been tampered with.
      def validate_assertion_digest_values
        return if all_assertion_digests_valid?

        self.errors << "SAML Response has been modified."
      end

      def all_assertion_digests_valid?
        # if there is a root sig, that will be validated by Xmldsig separately
        return true if has_root_sig_and_matching_ref?

        # note that we need to copy the doc here because we're going to modify it
        assertions = document.dup.xpath("//saml2:Assertion", namespaces)

        assertions.all? do |assertion|
          signature_ref = assertion.at("./ds:Signature/ds:SignedInfo/ds:Reference", namespaces)
          return false unless signature_ref
          assertion_id = String(assertion["ID"])
          ref_uri = String(String(signature_ref["URI"])[1..-1]) # chop off leading #
          return false unless ref_uri.length > 1
          return false unless assertion_id == ref_uri

          xml_signature_ref = Xmldsig::Reference.new(signature_ref)

          actual_digest = xml_signature_ref.digest_value
          calculated_digest = calculate_assertion_digest(assertion, xml_signature_ref)

          digest_valid = calculated_digest == actual_digest

          GitHub.logger.info(
            "Running all_assertion_digests_valid?",
            "saml.signature.digest_valid" => digest_valid,
            "saml.signature.calculated_digest" => Base64.encode64(calculated_digest),
            "saml.signature.actual_digest" => Base64.encode64(actual_digest),
            "saml.signature.assertion" => Base64.encode64(assertion&.to_s),
            "saml.signatures.count" => signatures&.count,
            "saml.assertions.count" => assertions&.count,
          )

          digest_valid
        end
      end

      def calculate_assertion_digest(assertion, xml_signature_ref)
        transformed = xml_signature_ref.transforms.apply(assertion)
        case transformed
        when String
          xml_signature_ref.digest_method.digest transformed
        when Nokogiri::XML::Node
          xml_signature_ref.digest_method.digest Xmldsig::Canonicalizer.new(transformed).canonicalize
        end
      end

      def self.namespaces
        {
          "ds" => "http://www.w3.org/2000/09/xmldsig#",
          "saml2p" => "urn:oasis:names:tc:SAML:2.0:protocol",
          "saml2" => "urn:oasis:names:tc:SAML:2.0:assertion",
        }
      end

      def namespaces
        self.class.namespaces
      end

      def validate_administrator(require_admin)
        return if GitHub.saml_disable_admin_demote
        return unless !!require_admin

        unless administrator_present?
          message = "SAML response must contain the administrator attribute with a value of true. \
            Please ensure this attribute is set for your user in your identity provider.".squish
          self.errors << message
        end
      end

      def administrator_present?
        attributes[:administrator]&.index("true")
      end

      # Private: Checks if runtime environment is codespaces within development and changes the service
      #   provider url to include business slug for development in a codespace environment
      #
      # Returns String
      def audience_url(sp_url)
        return sp_url unless GitHub.codespaces?

        business = GitHub.global_business
        return sp_url unless business

        "#{sp_url}/enterprises/#{business.slug}"
      end

      # These interfaces are from ruby-saml. We want to move away from this
      # because it assumes only a single assertion per response.
      module RubySamlCompatibility
        extend ActiveSupport::Concern

        included do
          attr_accessor :not_before       # UTC time
          attr_accessor :not_on_or_after  # UTC time
        end

        # {
        #   "urn:oid:0.9.2342.19200300.100.1.1" => ["jch"],
        #   "uid" => ["jch"],
        #   :"urn:oid:0.9.2342.19200300.100.1.1" => ["jch"],
        #   :uid => ["jch"]
        # }
        # Public: Set released assertion attributes. `attrs` is a hash keyed
        # attribute name.
        #
        # response.attributes = {"uid" => ["jch"]}
        def attributes=(attrs)
          @attributes = attrs
        end

        # Public: Returns hash of attributes about the principal.
        #
        def attributes
          @attributes || {}
        end

        private

        # Private: Validate assertion conditions. This belongs in
        # SAML::Message::Assertion, but leaving here to follow ruby-saml
        # interface.
        def validate_conditions
          return if SAML.mocked[:skip_conditions]

          now = Time.now

          if not_before && (now.to_i < not_before.to_i)
            self.errors << "Current time is earlier than NotBefore condition"
          end

          if not_on_or_after && (now >= not_on_or_after)
            self.errors << "Current time is on or after NotOnOrAfter condition"
          end
        end
      end
      include RubySamlCompatibility

    end
  end
end
