# typed: strict
# frozen_string_literal: true

module Settings
  class NodeinfoSoftwareController < ApplicationController
    extend T::Sig
    include Settings::ControllerMethods

    before_action :require_probe_enablement
    before_action :require_xhr
    before_action :login_required
    before_action :require_host_param

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Collab

    sig { void }
    def show
      result = SocialAccounts::NodeinfoProbe.call(host: host, defer_cache_write: true)

      if result.has_deferred_write?
        after_response do
          # Cache update, safe to do from a GET request.
          ActiveRecord::Base.connected_to(role: :writing) do
            result.perform_deferred_write
          end
        end
      end

      if result.failure?
        GitHub.logger.info(
          "nodeinfo-probe-failure",
          "code.namespace" => self.class.name,
          "code.function" => action_name,
          **result.details,
        )
      end

      render json: { software_name: result.software_name }
    end

    # This allows us to inject a test adapter in integration tests.
    sig { params(block: T.proc.params(f: Faraday::Connection).void).void }
    def self.faraday_conf_block=(block)
      SocialAccounts::NodeinfoProbe.faraday_conf_block = block
    end

    private

    sig { returns(String) }
    def host
      params.fetch(:host, "")
    end

    sig { void }
    def require_probe_enablement
      render_404 unless GitHub.nodeinfo_probe_enabled?
    end

    sig { void }
    def require_host_param
      render_404 unless host =~ %r{\A[^/]{1,255}\z}
    end

    # only would fail on an anon request and that is guarded against already
    sig { returns(Symbol) }
    def tenant_verification_enforceable
      :no
    end
  end
end
