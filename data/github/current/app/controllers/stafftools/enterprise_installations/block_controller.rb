# typed: true
# frozen_string_literal: true

class Stafftools::EnterpriseInstallations::BlockController < StafftoolsController
  def create
    EnterpriseInstallation.block(this_enterprise_installation.license_hash)
    redirect_to \
      stafftools_enterprise_installation_path(this_enterprise_installation),
      notice: "Enterprise Server installation license blocked."
  end

  def destroy
    EnterpriseInstallation.unblock(this_enterprise_installation.license_hash)
    redirect_to \
      stafftools_enterprise_installation_path(this_enterprise_installation),
      notice: "Enterprise Server installation license unblocked."
  end
end
