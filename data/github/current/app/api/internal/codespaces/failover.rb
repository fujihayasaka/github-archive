# typed: strict
# frozen_string_literal: true

class Api::Internal::Codespaces::Failover < Api::Internal::Codespaces::Hmac
  extend T::Sig

  post "/internal/codespaces/failover", operation_id: :internal do
    data = receive(Hash)
    vscs_target = data["vscs_target"].presence&.to_sym
    deliver_error!(400, message: "'vscs_target' is required") unless vscs_target

    authorize_vscs_target!(vscs_target)

    stamp = ::Codespaces::VscsServiceStamp.find(vscs_target: vscs_target, region: data["region"])
    deliver_error!(400, message: "unknown region '#{data["region"]}' for target '#{vscs_target}'") unless stamp
    deliver_error!(400, message: "unknown vscs_target '#{vscs_target}'") unless ::Codespaces::Vscs::TargetConfig.for(vscs_target)

    ::Codespaces::ToggleFailoverJob.perform_later(region: stamp.region.id, vscs_target: vscs_target, redirect: true, only: nil, codespaces_repository: nil, actor: nil)

    deliver_empty(status: 204)
  end

  get "/internal/codespaces/:name/failover", operation_id: :internal do
    codespace = Codespace.find_by(name: params[:name])
    deliver_error!(404) unless codespace
    authorize_vscs_target!(T.must(codespace.vscs_target).to_sym)

    failover_details = ::Codespaces::GetFailoverDetails.call(user: codespace.owner, region: codespace.location, vscs_target: codespace.vscs_target, is_copilot_workspace: codespace.copilot_workspace?)
    response = if failover_details
      {
        failover_region: failover_details[:failoverRegion],
        resume_failover_enabled: failover_details[:failoverEnabled],
      }
    else
      {
        failover_region: nil,
        resume_failover_enabled: false,
      }
    end

    deliver_raw(response)
  end
end
