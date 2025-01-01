# typed: true
# frozen_string_literal: true

class Organization::ProfileReadme::Public < Organization::ProfileReadme::Base
  def public?
    true
  end

  # The public configuration repository: .github
  def repository
    return @repository if defined?(@repository)
    @repository = organization.configuration_repository
  end

  def async_repository
    return Promise.resolve(@repository) if defined?(@repository)
    organization.async_configuration_repository.then do |org_config_repo|
      @repository = org_config_repo
    end
  end

  private

  def type
    "public"
  end

  def fetch_readme
    return nil unless repository.present?

    # TODO: do we need it to be async?
    repository.async_network.then do
      repository.org_profile_readme
    end
  end
end
