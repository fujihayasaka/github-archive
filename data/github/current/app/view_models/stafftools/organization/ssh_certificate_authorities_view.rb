# typed: true
# frozen_string_literal: true

module Stafftools
  module Organization
    class SshCertificateAuthoritiesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :org

      def cas
        org.ssh_certificate_authorities.all
      end
    end
  end
end
