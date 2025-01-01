# typed: true
# frozen_string_literal: true

module Codespaces
  class AuthController < ApplicationController
    include ApplicationController::CodespaceDependency

    with_options except: [
      :port_forwarding
    ] do
      before_action :require_codespace
      before_action :verify_authorization
    end
    before_action :require_codespace_port_forwarding, only: :port_forwarding
    before_action :set_codespace_context
    before_action :usage_allowed?

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Configurations,
      ApplicationRecord::Billing,
      ApplicationRecord::Spokes,
      only: [:port_forwarding]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      ApplicationRecord::Configurations,
      only: [:passthru]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:port_forwarding, :passthru],
      optional: true

    if Rails.env.development? && ENV["CODESPACES"]
      [
        :basic_auth_for_public_forwarded_ports,
        :login_required,
        :require_codespace,
        :verify_authorization,
        :set_codespace_context,
        :usage_allowed?,
      ].each do |filter|
        skip_before_action filter, only: :port_visibility_check
      end
    end

    def port_forwarding # rubocop:todo GitHub/UseRestfulActions
      GitHub.tracer.in_span("codespaces/auth_controller#port_forwarding", kind: :internal) do |_span|
        return render_404 unless params[:port] && params[:name] && params[:pb] && params[:id]

        port = parse_port_param&.first
        postback_uri = params[:pb]
        tunnel_name = params[:name]
        tunnel_id = params[:id]
        return render_404 unless valid_postback_uri(postback_uri:, tunnel_name:, port:)

        # Ensure the tunnel name matches the codespace name so we don't pass the token to the wrong codespace
        return render_404 unless tunnel_name == current_codespace.name

        token, visibility = Codespaces::FetchBasisTokenAndVisibility.call(codespace: current_codespace, port:)
        return render_404 unless token && visibility

        authorized, _ = GitHub.tracer.in_span("codespaces/auth_controller#AuthorizePortForwarding", kind: :internal) do |_span|
          Codespaces::AuthorizePortForwarding.call(
            user: current_user,
            codespace: current_codespace,
            visibility: visibility,
          )
        end
        return render_404 unless authorized

        skip_anti_phishing = current_user == current_codespace.owner

        GitHub.tracer.in_span("codespaces/auth_controller#render_port_forwarding", kind: :internal) do |_span|
          render "codespaces/auth/basis", locals: {
            postback_uri: postback_uri,
            access_token: token,
            port: port,
            tunnel_name: tunnel_name,
            tunnel_id: tunnel_id,
            skip_anti_phishing: skip_anti_phishing,
          }
        end
      end
    end

    def passthru # rubocop:todo GitHub/UseRestfulActions
      redirect_to codespace_path(current_codespace)
    end

    def mint_cascade_token # rubocop:todo GitHub/UseRestfulActions
      render json: { token: fetch_cascade_token }
    end

    def port_visibility_check # rubocop:todo GitHub/UseRestfulActions
      head 299
    end

    private

    def identifier # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      return @identifier if defined?(@identifier)

      @identifier = params[:identifier].presence ||
        params[:codespace_identifier].presence ||
        params[:workspace_identifier].presence ||
        name_from_url(params[:url])
    end

    def name_from_url(url)
      return unless url
      uri = URI.parse(url)
      uri.host&.split(".")&.first
    end

    def fetch_cascade_token(scope: nil, ports: nil)
      Codespaces::FetchCascadeToken.call(codespace: current_codespace, scope: scope, ports: ports)
    rescue Codespaces::Error => e
      Codespaces::ErrorReporter.report(e, codespace: current_codespace)
      nil
    end

    def require_codespace_port_forwarding
      render_404 unless current_codespace(scoped_to_user: false)
    end

    def valid_postback_uri(postback_uri:, tunnel_name:, port:)
      return false unless postback_uri && tunnel_name && port

      postback_uri_host = URI.parse(postback_uri).host
      domain_for_target = Vscs.dev_tunnels_domain_for_target(current_codespace.vscs_target)
      valid_uri_host = "#{tunnel_name}-#{port}.#{domain_for_target}"

      postback_uri_host == valid_uri_host
    end

    def parse_port_param
      port = params[:port]
      return [] if port.nil?
      port_num = port.to_i
      return [] if port_num <= 0
      [port_num]
    end
  end
end
