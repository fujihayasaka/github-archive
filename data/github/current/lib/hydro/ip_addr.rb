module Hydro
  class IpAddr
    def initialize(ip)
      @raw = ip

      begin
        @ip_address = ::IPAddr.new(ip)
      rescue IPAddr::AddressFamilyError, IPAddr::InvalidAddressError
        # Ignore invalid IPs
      end
    end

    def valid?
      @ip_address.present?
    end

    def to_s
      @raw
    end

    def ipv4_int
      ip_address.to_i if ipv4?
    end

    def ipv6_int
      ip_address.hton if ipv6?
    end

    def version
      if ipv4?
        :IPV4
      elsif ipv6?
        :IPV6
      end
    end

    private

    attr_reader :ip_address

    def ipv4?
      ip_address&.ipv4?
    end

    def ipv6?
      ip_address&.ipv6?
    end
  end
end
