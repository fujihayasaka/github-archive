# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::SshCertificateAuthoritiesController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required

  def destroy
    ca = this_business.ssh_certificate_authorities.find_by_id!(params[:id].presence&.to_i)
    unless ca
      flash[:error] = "SSH certificate authority not found"
      return redirect_to stafftools_enterprise_security_path(this_business)
    end

    if ca.destroy
      flash[:notice] = "SSH certificate authority destroyed"
    else
      flash[:error] = "Error deleting SSH certificate authority"
    end
    redirect_to stafftools_enterprise_security_path(this_business)
  end
end
