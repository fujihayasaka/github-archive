# frozen_string_literal: true

require "gpgme"
require "progeny"

# TODO: This initializer can be removed after Debian Jessie is deprecated
# Symetric encryption via password is not allowed in GPG 2.0, which is the
# default version for Debian Jessie. In that case fall back to using the
# (also installed) GPG 1.4 version.
if File.executable?("/usr/bin/gpg2") && File.executable?("/usr/bin/gpg")
  result = Progeny::Command.new("/usr/bin/gpg2", "--version")
  version_line = result.out.lines.first
  if result.status.success? && version_line.chomp =~ /2\.0\.(\d+)\z/
    GPGME::Engine.set_info(GPGME::PROTOCOL_OpenPGP, "/usr/bin/gpg", nil)
  end
end
