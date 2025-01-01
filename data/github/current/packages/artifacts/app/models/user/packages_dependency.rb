# typed: false
# frozen_string_literal: true

module User::PackagesDependency
  extend ActiveSupport::Concern

  def clashing_packages_namespace(new_login)

    begin
      if GitHub.flipper[:packages_namespace_retirement].enabled?
        meta = ::PackageRegistry::Twirp::MetadataClient.new
        resp = meta.check_packages_retired_namespace(
          owner_id: self.id, old_namespace: self.login, new_namespace: new_login)
        if resp.retired_namespace_exists
          return { clashing_packages_namespace: resp.first_retired_namespace, error: nil }
        end
      end
      { clashing_packages_namespace: nil, error: nil }
      rescue PackageRegistry::Twirp::InvalidArgumentError
        { clashing_packages_namespace: nil, error: "InvalidArgumentError" }
      rescue PackageRegistry::Twirp::Error => e
        GitHub::Logger.log_exception({ fn: "api.packages.check_packages_retired_namespace" }, e)
        { clashing_packages_namespace: nil, error: "InternalServerError" }
    end
  end

end
