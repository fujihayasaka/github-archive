# typed: true
# frozen_string_literal: true

# Required monkey patches for DNS resolution.
# See https://github.com/github/admin-experience/issues/1255

# Based on:
# https://github.com/ruby/ruby/blob/607aa11711a7975540e1d71c2616ae5533feb35a/lib/resolv.rb#L957-L986
class Resolv::DNS::Config
  def self.parse_resolv_conf(filename)
    nameserver = []
    search = T.let(nil, T.untyped)
    ndots = T.let(1, T.untyped)
    File.open(filename, "rb") do |f|
      f.each do |line|
        line.sub!(/[#;].*/, "")
        keyword, *args = line.split(/\s+/)
        # TODO [SORBET]: remove after upgrading Sorbet
        # This cast is the default behavior on Sorbet 0.5.11566
        args = T.cast(args, T::Array[String])
        next unless keyword
        case keyword
        when "nameserver"
          # Filter out any IPv6 link-local addresses from nameservers (for example
          # "fe80::5cb0:3cff:fe51:29b0%eth0"), as they cause a major bug when used
          # for DNS queries with Resolv.
          args.each do |ns|
            nameserver << ns unless ns =~ /\A.*\%[a-zA-Z0-9]*\z/
          end
        when "domain"
          next if args.empty?
          search = [T.must(args)[0]]
        when "search"
          next if args.empty?
          search = args
        when "options"
          T.must(args).each do |arg|
            case arg
            when /\Andots:(\d+)\z/
              ndots = $1.to_i
            end
          end
        end
      end
    end
    { nameserver: nameserver, search: search, ndots: ndots }
  end
end
