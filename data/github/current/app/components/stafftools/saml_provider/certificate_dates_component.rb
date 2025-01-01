# typed: true
# frozen_string_literal: true

class Stafftools::SamlProvider::CertificateDatesComponent < ApplicationComponent
  # param certificate [String] The certificate to parse
  # param classes [String] Classes to add to the component
  def initialize(certificate:, classes: nil)
    @certificate = OpenSSL::X509::Certificate.new(certificate)
    @time_format = "%-d %b %Y, %l:%M%P %z"
    @classes = classes
  rescue OpenSSL::X509::CertificateError => exception_message
    @exception_message = exception_message
  end

  def now_is_before
    Time.now.utc < @certificate.not_before
  end

  def now_is_after
    Time.now.utc > @certificate.not_after
  end

end
