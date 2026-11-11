# typed: true
# frozen_string_literal: true

# This class is meant to be called by codespaces port forwarding service.
class Api::Internal::Codespaces::PortForwarding < Api::Internal::Codespaces::Hmac
  # This will be used by port forwarding service (PFS) and the portal. The idea is that user can provide github token to PFS or the portal so that
  # they can use a REST client to view contents on a non-public port (org or private). PFS works with cascade token so
  # we need a way for PFS to be able to get a cascade token. So, it will make a service to service (HMAC header) call
  # with user's token (Auth header) to get the appropriate cascade token. The portal does not need the cascade token for
  # for the basis migration so there is an optional parameter being passed in for if we need to fetch the token. The
  # default is set to always mint the cascade token (unless we pass in false)
  # The use of "read_codespaces_for_repo_public" is intentional to support org scoped ports in which a user A can see
  # the contents of user B if B forwards a port with "org" visiblity. In this case, if both users are in same org and
  # have access to the repository that the codespace was created for, we should allow that.
  get "/internal/codespaces/:codespace_name/cascade_token", operation_id: :internal do
    @route_owner = "@github/codespaces"

    validate_params

    # fetch the codespace
    current_codespace = record_or_404(
      Codespace.find_by(name: params[:codespace_name])
    )

    authorize_vscs_target!(current_codespace.vscs_target&.to_sym)

    control_access :read_codespaces_for_repo_public,
      resource: current_codespace.repository,
      repo: current_codespace.repository,
      challenge: true,
      forbid: current_codespace.present?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    authorized, scope = ::Codespaces::AuthorizePortForwarding.call(
      user: current_user,
      codespace: current_codespace,
      visibility: params[:visibility].downcase,
    )

    deliver_error!(403, message: "PortForwarding Authorizing Failed") unless authorized

    # see if we need to fetch the cascade token using the optional parameter
    if !params.has_key?(:should_fetch_cascade_token) || params[:should_fetch_cascade_token] == "true"
      deliver_raw(
        {
          token: fetch_cascade_token(scope: scope, ports: parse_port_param, current_codespace: current_codespace),
        },
      )
    end


  end

  private

  def fetch_cascade_token(scope:, ports:, current_codespace:)
    ::Codespaces::FetchCascadeToken.call(codespace: current_codespace, scope: scope, ports: ports)
  rescue ::Codespaces::Error => e
    ::Codespaces::ErrorReporter.report(e, codespace: current_codespace)
    nil
  end

  def parse_port_param
    port = params[:port]
    port_num = port.to_i
    return [] if port_num <= 0
    [port_num]
  end

  def validate_params
    deliver_error!(400, message: "visibility parameter is missing") unless params[:visibility]
    deliver_error!(400, message: "port parameter is missing") unless params[:port]
  end
end
