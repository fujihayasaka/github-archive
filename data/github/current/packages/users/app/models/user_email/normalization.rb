# typed: true
# frozen_string_literal: true

class UserEmail::Normalization
  LOCAL_PART_NORMALIZATIONS = {
    %w(gmail.com) => /\.+/,
  }

  SUBADDRESSES = {
    %w(gmail.com) => /\+.*\z/,
    %w(icloud.com mac.com me.com) => /\+.*\z/,
    %w(outlook.com) => /\+.*\z/,
    %w(yahoo.com ymail.com) => /\-.*\z/,
  }

  attr_reader :address

  def initialize(address)
    raise ArgumentError unless User.valid_email?(address)

    @address = address
  end

  def normalized_address
    "#{ remove_subaddress(normalize_local(local)) }@#{ domain }"
  end

  private

  def local
    address.split("@", 2).first.downcase
  end

  def domain
    address.split("@", 2).last.downcase
  end

  def local_part_normalization_rule
    match = LOCAL_PART_NORMALIZATIONS.find do |(domains, _)|
      domains.include?(domain)
    end

    match && match[1]
  end

  def normalize_local(local_address)
    return local_address unless local_part_normalization_rule

    local_address.gsub(local_part_normalization_rule, "")
  end

  def subaddress_rule
    match = SUBADDRESSES.find do |(domains, _)|
      domains.include?(domain)
    end

    match && match[1]
  end

  def remove_subaddress(local_address)
    return local_address unless subaddress_rule

    local_address.gsub(subaddress_rule, "")
  end
end
