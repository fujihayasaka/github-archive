# typed: true
# frozen_string_literal: true

class Stafftools::SamlProvider::CertificateSubjectComponent < ApplicationComponent
  # param certificate [String] The certificate to parse
  def initialize(certificate:, classes: nil)
    @certificate = OpenSSL::X509::Certificate.new(certificate)
    @classes = classes
  rescue OpenSSL::X509::CertificateError => exception_message
    @exception_message = exception_message
  end
end
