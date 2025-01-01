# typed: true
# frozen_string_literal: true

module Repos::AdvisoriesHelper
  extend T::Helpers
  extend T::Sig
  requires_ancestor { ViewModel }

  def repository_advisory_page_title(advisory)
    # application_helper.rb#page_title, which receives this string, modifies
    # its input - so we have to ensure this string is not frozen.
    +"#{advisory_title(advisory)} · Advisory · #{current_repository.name_with_owner}"
  end

  def advisory_title(advisory)
    advisory.get_title(current_user).dup&.force_encoding("UTF-8")&.scrub
  end

  def advisory_package_ecosystem(ecosystem)
    ecosystem = ecosystem.to_s.upcase.to_sym
    ecosystem = :BUNDLER if ecosystem == :RUBYGEMS
    ecosystem = :GOMOD if ecosystem == :GO
    ecosystem = :CARGO if ecosystem == :RUST
    serialized = Dependabot.serialize_package_ecosystem(package_ecosystem: ecosystem)
    serialized != "unknown" ? ecosystem : nil
  end

  sig { params(repository: Repository, check_spammy: T::Boolean).returns(T::Boolean) }
  def use_pvd_workflow?(repository: current_repository, check_spammy: true)
    return @pvd_authorized if defined?(@pvd_authorized)

    @pvd_authorized = AdvisoryDB::Pvd.authorized?(
      repo: repository,
      user: current_user,
      check_spammy: check_spammy
    )
  end
end
