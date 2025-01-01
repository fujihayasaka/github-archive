# typed: true
# frozen_string_literal: true

class Stafftools::SshAuditController < StafftoolsController
  before_action :ensure_ssh_audit_enabled

  def create
    GitHub.instrument("enterprise.ssh_audit_start", { actor: current_user.display_login, actor_id: current_user.id })
    PublicKey.update_all(verified_at: nil)
    redirect_to stafftools_users_path, notice: "Public key audit has started."
  end

  private

  def ensure_ssh_audit_enabled
    render_404 unless GitHub.ssh_audit_enabled?
  end
end
