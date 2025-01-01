# typed: true
# frozen_string_literal: true

class RepositoryAdvisory::CVE
  def self.request_cve(advisory, current_user)
    GlobalInstrumenter.instrument("repository_advisory.request_cve", {
      repository_advisory: advisory,
      actor: current_user,
    })

    advisory.cve_request_pending!
    advisory.add_cve_requested_event(current_user)
  end

  sig { params(advisory: ::RepositoryAdvisory).returns(T::Boolean) }
  def self.cve_requestable?(advisory)
    !!(!advisory.closed? &&
      advisory.form_filled_out? &&
      advisory.cve_id.blank? &&
      !T.must(advisory.repository).empty? &&
      !advisory.description_matches_template? &&
      !AdvisoryDB::Innersource.eligible_repo?(repo: advisory.repository))
  end
end
