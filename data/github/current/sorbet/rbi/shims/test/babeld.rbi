# typed: true

module BabeldCommon
  extend T::Helpers

  abstract!

  def babeld_server; end
  def babeld_config_file; end
  def git_server; end
  def gitrpcd_server; end
  def gitauth_server; end
  def postrx_server; end

end
