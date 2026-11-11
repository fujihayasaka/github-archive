# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Licensing
  module CodeQualityLicensifyEnablement
    private

    sig { params(repo: Repository).returns(T::Boolean) }
    def code_quality_enabled_for_licensify?(repo)
      CodeQualityEnablement.new(repo).enabled?
    rescue CodeScanning::AutoCodeqlError => error
      Failbot.report(error)
      GitHub.logger.warn(
        "Skipping Code Quality product enablement after Turboscan lookup failed",
        "code.namespace": T.unsafe(self).class.name,
        "code.function": "code_quality_enabled_for_licensify?",
        "gh.repo.id": repo.id,
        "gh.customer.id": Licensing::Customer.id_for(repo),
        "code.error.class": error.class.name,
        "code.error.message": error.message,
      )
      false
    end
  end
end
